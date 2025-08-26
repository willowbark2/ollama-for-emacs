
# ollama-for-emacs

## Description

ollama-for-emacs is an emacs extension which provides two functions "ask" and "code" that help with software development.

* "ask" answers the query in a new buffer, so it doesn't interfere with your current program.
* "code" performs code completion. The function extracts the first code block returned by the language model and erases the rest of the response.

## Usage

Highlight a region of text to send to the ollama host, then run one of the following:

 * Invoke ask: `M-x ask`
 * Code completion: `M-x code`

Move the cursor inside of a word that represents a python object.
  * Get help: `C-p`

For example, move your text cursor inside of the word `df`, then hit `C-p`:
```python
df = pd.read_csv('data.csv')
```

This will use the AI model to extract the model name `pandas` and the object type `pandas.core.frame.DataFrame`, then it prints the python doc string:
```shell
python -c 'import pandas; print(pandas.core.frame.DataFrame.__doc__)'
```


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

(add-hook 'python-mode-hook (lambda ()
  (global-set-key (kbd "C-p") #'py-help)))
```
