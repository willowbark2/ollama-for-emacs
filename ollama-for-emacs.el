;;; ollama-for-emacs.el --- Stream code completion for region via Ollama  -*- lexical-binding: t; -*-
;;;
;;; Copyright (C) 2025 by willowbark2
;;;
;;; Permission to use, copy, modify, and/or distribute this software
;;; for any purpose with or without fee is hereby granted.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
;;; WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
;;; MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
;;; ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
;;; WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
;;; ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
;;; OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
;;;

(require 'json)
(require 'subr-x)
(require 'cl-lib)
(require 'thingatpt)

;(global-set-key "\C-p" 'thing-at-point--identifier)
;(global-set-key (kbd "C-p") #'get-word-under-cursor)
;(global-set-key (kbd "C-p") #'get-line-under-cursor)
(global-set-key (kbd "C-p") #'py-help)


(defun get-word-under-cursor ()
  (thing-at-point 'symbol))

(defun get-line-under-cursor ()
  (buffer-substring-no-properties (line-beginning-position) (line-end-position)))

(defun strip (text)
  (replace-regexp-in-string "^[ \t\n\r]+\\|[ \t\n\r]+$" "" text))


  (defun py-help-object-clean-ai-response (text)
    (let* (
           (text (strip text))
           (text (when (string-prefix-p "```python\n" text) (substring text 10)))
           (text (when (string-suffix-p "\n```" text) (substring text 0 -4)))
           (text (strip text))
           (text (when (string-prefix-p "<class '" text) (substring text 8)))
           (text (when (string-suffix-p "'>" text) (substring text 0 -2))))
      text))

(defun py-help ()
  (interactive)
  (let* (
      (object-at-point (get-word-under-cursor))
      (current-line (get-line-under-cursor))
      (prompt (format "Relevant object: `%s`\nRelevant line:\n```python\n%s\n```\n\nPretend you are a python interpreter. What type of object is `%s`?\nRespond with the exact python data type as returned by python's function, `type()`.\n```python\ntype(%s)\n```\nReturn your response as a code block in markdown format using three backticks." object-at-point current-line object-at-point object-at-point))
      (ai-response (ollama-send-message prompt))
      (object-type (py-help-object-clean-ai-response ai-response))
      (python-module (car (split-string object-type "\\.")))
      (help-text (shell-command-to-string (format "python3 -c 'import %s; print(%s.__doc__)'" python-module object-type)))
      (buf (get-buffer-create (format "*help-%s*" object-at-point))))
    (progn
      (with-current-buffer buf
        (erase-buffer)
        (insert "\n\n")
        (insert (format "LINE:    %s\n" current-line))
        (insert (format "OBJECT:  %s\n" object-at-point))
        (insert (format "MODULE:  %s\n" python-module))
        (insert (format "TYPE:    %s\n" object-type))
        (insert (format "\n\n>>> help(%s)\n\n" object-type))
        (insert help-text))
      (switch-to-buffer buf)
      (goto-char (point-min)))))


(defun ollama-send-message (prompt &optional system-message model host port)
  "Send PROMPT to a local Ollama /api/chat endpoint using curl.
Return the assistant's reply as a string, or nil on error."
  (let* ((model (or model "qwen3-coder:30b"))
         (host  (or host "localhost"))
         (system-message (or system-message "You are an AI assistant."))
         (port  (or port 11434))
         (url   (format "http://%s:%s/api/chat" host port))
         (history (vector
                   `(("role" . "system")
                     ("content" . system-message))
                   `(("role" . "user")
                     ("content" . ,prompt))))
         (payload `(("model"    . ,model)
                    ("messages" . ,history)
                    ("stream"   . :json-false)
                    ("options"  . (("temperature"   . 0.1)
                                   ("repeat_last_n" . -1)
                                   ("top_k"         . 10)
                                   ("top_p"         . 0.95)))))
         (json-request (json-encode payload))
         (stdout-buf (generate-new-buffer " *ollama-curl*"))
         (stderr-file (make-temp-file "ollama-stderr"))
         reply)
    (unwind-protect
        (let ((exit-code
               (with-temp-buffer
                 (insert json-request)
                 (call-process-region
                  (point-min) (point-max)
                  "curl" nil (list stdout-buf stderr-file) nil
                  "-sS" "-f"
                  "-H" "Content-Type: application/json"
                  "-X" "POST" url
                  "--data-binary" "@-"))))
          (if (zerop exit-code)
              (with-current-buffer stdout-buf
                (let* ((json-object-type 'alist)
                       (json-array-type 'list)
                       (json (json-read-from-string (buffer-string)))
                       (message-obj (alist-get 'message json))
                       (content (alist-get 'content message-obj)))
                  (setq reply (and (stringp content)
                                   (string-trim content)))))
            (let ((err (when (file-exists-p stderr-file)
                         (with-temp-buffer
                           (insert-file-contents stderr-file)
                           (string-trim (buffer-string))))))
              (message "Ollama API error: %s"
                       (if (and err (not (string-empty-p err)))
                           err
                         "no details")))))
      (when (buffer-live-p stdout-buf) (kill-buffer stdout-buf))
      (when (file-exists-p stderr-file) (delete-file stderr-file)))
    reply))




(defgroup ollama-for-emacs nil
  "Stream code completions for the active region from an Ollama server."
  :group 'tools
  :prefix "ollama-for-emacs-")

(defcustom ollama-host "http://localhost:11434"
  "Base URL of the Ollama server."
  :type 'string :group 'ollama-for-emacs)

(defcustom ollama-model "qwen3-coder:30b"
  "Default Ollama model to use for completions."
  :type 'string :group 'ollama-for-emacs)

(defcustom temperature 0.1
  "Sampling temperature for the model."
  :type 'number :group 'ollama-for-emacs)

(defcustom ollama-max-tokens nil
  "Optional token limit for generation (nil lets the server decide)."
  :type '(choice (const :tag "Unlimited / server default" nil) integer)
  :group 'ollama-for-emacs)

(defcustom allow-code-fences nil
  "If non-nil, allow Markdown code fences (```...```) to remain in final output."
  :type 'boolean :group 'ollama-for-emacs)

(defcustom preserve-tabs t
  "If non-nil, convert leading indentation spaces to tabs in the generated text."
  :type 'boolean :group 'ollama-for-emacs)

(defcustom user-tab-width 4
  "Tab width used when converting leading spaces to tabs in generated text."
  :type 'integer :group 'ollama-for-emacs)

(defcustom thinking-open "<thinking>\n"
  "Opening XML marker inserted before streaming."
  :type 'string :group 'ollama-for-emacs)

(defcustom thinking-close "\n</thinking>"
  "Closing XML marker inserted after streaming starts."
  :type 'string :group 'ollama-for-emacs)

(defcustom answer-open "\n<answer>\n"
  "Opening XML marker inserted before streaming."
  :type 'string :group 'ollama-for-emacs)

(defcustom answer-close "\n</answer>"
"Closing XML marker inserted after streaming starts."
:type 'string :group 'ollama-for-emacs)


;; -------- Internal state --------
(defvar-local ollama--proc nil)
(defvar-local ollama--partial "")
(defvar-local ollama--origin-buffer nil)

;; Markers for thinking tags + streamed area
(defvar-local ollama--think-open-start nil)  ;; start of "<thinking>\n"
(defvar-local ollama--insert-start nil)      ;; just after open tag (start of streamed content)
(defvar-local ollama--insert-marker nil)     ;; moving insertion point (before close tag)
(defvar-local ollama--think-close-start nil) ;; start of "</thinking>" tag

;; Echo suppression
(defvar-local ollama--skip-prefix nil)       ;; exact region text we sent
(defvar-local ollama--skip-pos 0)

(defun ollama--alive-p () (and ollama--proc (process-live-p ollama--proc)))
(defun ollama--endpoint (path) (concat (string-remove-suffix "/" ollama-host) path))

(defun insert-to-new-buffer (text buffer-name)
  "Insert TEXT into new BUFFER-NAME."
  (switch-to-buffer (get-buffer-create buffer-name))
  (erase-buffer)
  (insert text)
  (goto-char (point-min)))


(defun delete-code-fences ()
  "Delete two regions in sequence from the current buffer:
1. From a line starting with `<thinking>` through the line containing only ```
2. From a line containing only ``` through the line containing `</thinking>`.
Deletes all occurrences of these regions."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    ;; Delete all <thinking> ... ```
    (while (re-search-forward "<thinking>$" nil t)
      (let ((start (match-beginning 0)))
        (if (re-search-forward "^```[a-z]+$" nil t)
            (delete-region start (point))
          (delete-region start (point-max)))))

    ;; Delete all ```
    (goto-char (point-min))
    (while (re-search-forward "^```$" nil t)
      (let ((start (match-beginning 0)))
        (when (re-search-forward "^</thinking>$" nil t)
          (delete-region start (point)))))))

(defun tabify-multispaced-lines ()
  "Replace blocks of 4 leading spaces with tabs on lines starting with multiples of 4 spaces."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      (when (looking-at "^\\(    \\)+") ; lines starting with multiples of 4 spaces
        (tabify (line-beginning-position) (line-end-position)))
      (forward-line 1))))

(defun ollama--insert-thinking-tags (pos)
  "Insert <thinking> and </thinking> at POS and set markers so streaming happens between them."
  (with-current-buffer ollama--origin-buffer
    (save-excursion
      (goto-char pos)
      (insert thinking-open)
      (setq ollama--think-open-start (copy-marker (- (point) (length thinking-open))))
      (setq ollama--insert-start     (copy-marker (point)))
      (insert thinking-close)
      (setq ollama--think-close-start (copy-marker (- (point) (length thinking-close))))
      (setq ollama--insert-marker     (copy-marker ollama--think-close-start t)))))

(defun ollama--insert-answer-tags (pos)
  "Insert <answer> and </answer> at POS and set markers so streaming happens between them."
  (with-current-buffer ollama--origin-buffer
    (save-excursion
      (goto-char pos)
      (insert answer-open)
      (setq ollama--think-open-start (copy-marker (- (point) (length answer-open))))
      (setq ollama--insert-start     (copy-marker (point)))
      (insert answer-close)
      (setq ollama--think-close-start (copy-marker (- (point) (length answer-close))))
      (setq ollama--insert-marker     (copy-marker ollama--think-close-start t)))))


(defun ollama--insert (text)
  (when (and (markerp ollama--insert-marker) (buffer-live-p ollama--origin-buffer))
    (with-current-buffer ollama--origin-buffer
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char ollama--insert-marker)
          (insert text)
          (set-marker ollama--insert-marker (point)))))))

(defun ollama--consume-echo (s)
  "Consume leading echo of the prompt from S (only at the beginning of the stream)."
  (let ((pos 0) (len (length s)))
    (when (and ollama--skip-prefix (< ollama--skip-pos (length ollama--skip-prefix)))
      (let ((limit (min len (- (length ollama--skip-prefix) ollama--skip-pos))))
        (while (and (< pos limit)
                    (eq (aref s pos)
                        (aref ollama--skip-prefix (+ ollama--skip-pos pos))))
          (setq pos (1+ pos))))
      (setq ollama--skip-pos (+ ollama--skip-pos pos)))
    (substring s pos)))

;; -------- Post-processing helpers --------
(defun ollama--first-fenced-slice (text)
  "Return (START . END) of first ```...``` fenced block in TEXT, or nil."
  (let ((open (string-match "```" text)))
    (when open
      (let* ((after-open (+ open 3))
             (nl (string-match "\n" text after-open))
             (content-start (if nl (1+ nl) after-open))
             (close (string-match "```" text content-start)))
        (when (and close (> close content-start))
          (cons content-start close))))))

(defun ollama--drop-fence-lines (s)
  "Remove any lines containing triple backticks from S unless fences are allowed."
  (if allow-code-fences s
    (let ((out '()))
      (dolist (ln (split-string s "\n" -1))
        (unless (string-match-p "```" ln) (push ln out)))
      (mapconcat #'identity (nreverse out) "\n"))))

(defun ollama--prompt-line-set (prompt)
  "Hash set of lines in PROMPT for exact-equality echo removal."
  (let ((h (make-hash-table :test 'equal)))
    (dolist (ln (split-string (or prompt "") "\n" -1)) (puthash ln t h))
    h))

(defun ollama--prose-line-p (line)
  "Heuristic: returns t if LINE is likely prose, not code."
  (let* ((trim (string-trim-right line))
         (raw  (string-trim-left trim)))
    (cond
     ((string-empty-p raw) nil) ; keep blanks
     ((string-match-p "\\`[ \t]*#.*\\'" raw) nil)
     ((string-match-p "\\`[ \t]*```" raw) t)
     ((string-match-p "\\`[ \t]*\\(def\\|class\\|if\\|elif\\|else\\|for\\|while\\|try\\|except\\|finally\\|with\\|return\\|yield\\|import\\|from\\|pass\\|break\\|continue\\|raise\\|global\\|nonlocal\\)\\b" raw) nil)
     ((string-match-p "\\`[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*(" raw) nil)
     ((string-match-p "[(){}\\[\\]:=;,.<>+\\-/*%]" raw) nil)
     (t (let ((words (split-string raw "[ \t]+" t))) (>= (length words) 4))))))

(defun ollama--retabify (beg end)
  (when (and preserve-tabs (< beg end))
    (save-restriction
      (narrow-to-region beg end)
      (goto-char (point-min))
      (let ((tab-width user-tab-width))
        (while (not (eobp))
          (let ((bol (line-beginning-position))
                (bti (progn (back-to-indentation) (point))))
            (when (< bol bti) (tabify bol bti)))
          (forward-line 1))))))

;; -------- Post-processing pipeline --------
(defun ollama--postprocess ()
  "Keep only first fenced code block inside <thinking>…</thinking>, strip fences/prose/echo, preserve tabs."
  (when (and (markerp ollama--think-open-start)
             (markerp ollama--insert-start)
             (markerp ollama--think-close-start)
             (buffer-live-p ollama--origin-buffer))
    (with-current-buffer ollama--origin-buffer
      (let ((beg (marker-position ollama--insert-start))
            (end (marker-position ollama--think-close-start)))
        (when (and beg end (< beg end))
          (save-excursion
            (let* ((raw (buffer-substring-no-properties beg end))
                   (slice (ollama--first-fenced-slice raw))
                   (candidate (if slice
                                  (substring raw (car slice) (cdr slice))
                                raw)))
              ;; remove any fence lines inside the candidate unless allowed
              (setq candidate (ollama--drop-fence-lines candidate))
              ;; drop lines that exactly echo the prompt
              (let ((plines (ollama--prompt-line-set ollama--skip-prefix))
                    (kept '()))
                (dolist (ln (split-string candidate "\n" -1))
                  (unless (gethash ln plines) (push ln kept)))
                (setq candidate (mapconcat #'identity (nreverse kept) "\n")))
              ;; Remove prose/explanations from the generated block after extraction.
              (let ((kept '()))
                (dolist (ln (split-string candidate "\n" -1))
                  (unless (ollama--prose-line-p ln) (push ln kept)))
                (setq candidate (mapconcat #'identity (nreverse kept) "\n")))
              ;; trim extra blank lines
              (setq candidate (replace-regexp-in-string "\\`\\(\n\\)+" "" candidate))
              (setq candidate (replace-regexp-in-string "\\(\n\\)+\\'" "\n" candidate))
              ;; replace streamed region
              (goto-char beg)
              (delete-region beg end)
              (insert candidate)
              (let ((new-end (+ beg (length candidate))))
                ;; retabify only the inserted block
                (ollama--retabify beg new-end))
              ;; finally remove </thinking> and <thinking>
              (let* ((close-beg (marker-position ollama--think-close-start))
                     (close-len (length thinking-close)))
                (when close-beg (delete-region close-beg (+ close-beg close-len))))
              (let* ((open-beg (marker-position ollama--think-open-start))
                     (open-end (marker-position ollama--insert-start)))
                (when (and open-beg open-end) (delete-region open-beg open-end))))))))))

;; -------- Process lifecycle --------
(defun ollama--cleanup (&optional msg)
  (when (ollama--alive-p) (ignore-errors (delete-process ollama--proc)))
  (setq ollama--proc nil
        ollama--partial ""
        ollama--origin-buffer nil
        ollama--skip-prefix nil
        ollama--skip-pos 0)
  (dolist (m (list
              ollama--think-open-start
              ollama--insert-start
              ollama--insert-marker
              ollama--think-close-start))
    (when (markerp m) (set-marker m nil)))
  (setq ollama--think-open-start nil
        ollama--insert-start nil
        ollama--insert-marker nil
        ollama--think-close-start nil)
  (when msg (message "%s" msg)))

(defun ollama--finish (&optional msg)
  "Finish processing"
  (ollama--postprocess)
  (ollama--cleanup msg)
  (tabify-multispaced-lines)
  (delete-code-fences))

(defun ollama-stop-stream ()
  "Stop the current Ollama streaming completion."
  (interactive)
  (if (ollama--alive-p)
      (ollama--finish "Ollama stream stopped.")
    (message "No Ollama stream is running.")))

(defun ollama--process-sentinel (_proc event)
  (let ((msg (string-trim event)))
    (unless (string-empty-p msg)
      (message "Ollama: %s" msg))))

(defun ollama--process-filter (_proc chunk)
  "Handle streaming NDJSON from curl."
  (setq ollama--partial (concat ollama--partial chunk))
  (let* ((parts (split-string ollama--partial "\n"))
         (lines (butlast parts))
         (remainder (car (last parts))))
    (setq ollama--partial remainder)
    (dolist (line lines)
      (let ((s (string-trim-right line)))
        (unless (string-empty-p s)
          (let ((obj (ignore-errors
                       (if (fboundp 'json-parse-string)
                           (json-parse-string s :object-type 'alist)
                         (json-read-from-string s)))))
            (when obj
              (let ((resp (alist-get "response" obj nil nil #'string=))
                    (done (alist-get "done"     obj nil nil #'string=))
                    (err  (alist-get "error"    obj nil nil #'string=)))
                (when err (ollama--finish (format "Ollama error: %s" err)))
                (when resp
                  (let ((emit (ollama--consume-echo resp)))
                    (when (> (length emit) 0)
                      (ollama--insert emit))))
                (when (eq done t) (ollama--finish "Ollama: done."))
                ))))))))


(defun code (beg end)
  "Stream a code completion for the region from an Ollama server.
Inserts tokens inside <thinking>…</thinking> placed after END.
When done, removes <thinking>...```language\n and ```...</thinking>
Press C-x g to stop streaming."
  (interactive "r")
  (unless (use-region-p) (user-error "Select a region first"))
  (when (ollama--alive-p) (user-error "Another Ollama stream is already running"))
  (unless (executable-find "curl") (user-error "curl is required but was not found in PATH"))
  (let* ((region-text (buffer-substring-no-properties beg end))
         (options
          (delq nil
                (list
                 (cons "temperature" temperature)
                 (when ollama-max-tokens
                   (cons "num_predict" ollama-max-tokens)))))
         (payload (json-encode
                   (list (cons "model"   ollama-model)
                         (cons "prompt"  region-text)
                         (cons "stream"  t)
                         (cons "options" options))))
         (url (ollama--endpoint "/api/generate"))
         (cmd `("curl" "-sS" "--no-buffer" "-X" "POST" "-H" "Content-Type: application/json" "-d" ,payload ,url))
         (tmp-buf (generate-new-buffer " *ollama-for-emacs*")))
    (setq ollama--origin-buffer (current-buffer))
    ;; Insert XML tags and stream between them
    (ollama--insert-thinking-tags end)
    (setq ollama--partial "" ollama--skip-prefix region-text ollama--skip-pos 0)
    (setq ollama--proc
          (make-process
           :name "ollama-for-emacs"
           :buffer tmp-buf
           :command cmd
           :connection-type 'pipe
           :noquery t
           :filter #'ollama--process-filter
           :sentinel (lambda (p e)
                       (when (buffer-live-p tmp-buf) (kill-buffer tmp-buf))
                       (ollama--process-sentinel p e))))
    ;; Cancel key: C-x g
    (let ((map (make-sparse-keymap)))
      (define-key map (kbd "C-x g") #'ollama-stop-stream)
      (set-transient-map map (lambda () (ollama--alive-p))))
    (message "Ollama: streaming… press C-x g to stop.")))


(defun ask (beg end)
  "Ask the LLM a question. Press C-x g to stop streaming."
  (interactive "r")
  (unless (use-region-p) (user-error "Select a region first"))
  (when (ollama--alive-p) (user-error "Another Ollama stream is already running"))
  (unless (executable-find "curl") (user-error "curl is required but was not found in PATH"))
  (let* ((region-text (buffer-substring-no-properties beg end))
         (options
          (delq nil
                (list
                 (cons "temperature" temperature)
                 (when ollama-max-tokens
                   (cons "num_predict" ollama-max-tokens)))))
         (payload
          (json-encode
           (list (cons "model"   ollama-model)
                 (cons "prompt"  region-text)
                 (cons "stream"  t)
                 (cons "options" options))))
         (url (ollama--endpoint "/api/generate"))
         (cmd `("curl" "-sS" "--no-buffer" "-X" "POST" "-H" "Content-Type: application/json" "-d" ,payload ,url))
         (tmp-buf (generate-new-buffer " *ollama-for-emacs*")))
    (setq answer-buffer (get-buffer-create "*answer*"))
    (switch-to-buffer answer-buffer)
    (setq ollama--origin-buffer answer-buffer)
    ;; Insert XML tags and stream between them
    (ollama--insert-answer-tags end)
    (setq ollama--partial "" ollama--skip-prefix region-text ollama--skip-pos 0)
    (setq ollama--proc
          (make-process
           :name "ollama-ask"
           :buffer tmp-buf
           :command cmd
           :connection-type 'pipe
           :noquery t
           :filter #'ollama--process-filter
           :sentinel (lambda (p e)
                       (when (buffer-live-p tmp-buf) (kill-buffer tmp-buf))
                       (ollama--process-sentinel p e))))
    ;; Cancel key: C-x g
    (let ((map (make-sparse-keymap)))
      (define-key map (kbd "C-x g") #'ollama-stop-stream)
      (set-transient-map map (lambda () (ollama--alive-p))))
    (message "Ollama: streaming… press C-x g to stop.")))



(provide 'ollama-for-emacs)

;; Local Variables:
;; indent-tabs-mode: nil
;; lisp-body-indent: 2
;; tab-width: 2
;; End:
