
# ollama-for-emacs

## Description

ollama-for-emacs is an emacs extension which provides two functions "ask" and "code" that help with software development.

* "ask" answers the query in a new buffer, so it doesn't interfere with your current program.
* "code" performs code completion. The function extracts the first code block returned by the language model and erases the rest of the response.

## Usage

Highlight a region of text to send to the ollama host, then run one of the following:

 * Invoke ask: `M-x ask`
 * Code completion: `M-x code`

## Installation

Copy `ollama-for-emacs.el` into your `~/.emacs.d/lisp` directory

Add the following to your `~/.emacs` file.
```lisp
  (add-to-list 'load-path "~/.emacs.d/lisp/ollama-for-emacs.el")
  (require 'ollama-for-emacs)
```

Set the following options to suit your needs:
```lisp
  (setq ollama-for-emacs-host "http://localhost:11434")
  (setq ollama-for-emacs-model "qwen3-coder:30b")
  (setq ollama-for-emacs-temperature 0.1)
```
