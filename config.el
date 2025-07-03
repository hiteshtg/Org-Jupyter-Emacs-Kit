(require 'package)
(setq package-archives
      '(("melpa" . "https://melpa.org/packages/")
        ("gnu"   . "https://elpa.gnu.org/packages/")
        ("org"   . "https://orgmode.org/elpa/")))
(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

(use-package exec-path-from-shell
  :ensure t
:init (exec-path-from-shell-initialize))

(use-package dashboard
  :config
  (setq dashboard-startup-banner "~/.emacs.d/dragon_dashboard.txt"
        dashboard-items '((recents  . 5)
                          (projects . 5)
                          (agenda   . 5))
	initial-buffer-choice (lambda () (get-buffer "*dashboard*")))
  (dashboard-setup-startup-hook)

(add-hook 'after-make-frame-functions
            (lambda (frame)
              (with-selected-frame frame
                (dashboard-refresh-buffer)))))

(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

(use-package doom-themes
  :ensure t
  :init
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  :config
  (load-theme 'doom-one t))

(use-package all-the-icons)

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

(global-set-key (kbd "C-=") 'text-scale-increase)
(global-set-key (kbd "C--") 'text-scale-decrease)

(use-package ivy
  :ensure t
  :diminish
  :init
    (ivy-mode 1)
  :bind (("C-s" . swiper)
         :map ivy-minibuffer-map
         ("TAB" . ivy-alt-done)
         ("C-l" . ivy-alt-done)
         ("C-j" . ivy-next-line)
         ("C-k" . ivy-previous-line))
  :config
  (setq ivy-use-virtual-buffers t)
  (setq ivy-count-format "(%d/%d) "))

(use-package counsel
  :after ivy
  :bind (("M-x" . counsel-M-x)
         ("C-x C-f" . counsel-find-file)
         ("C-c k" . counsel-rg)
         ("C-x b" . counsel-switch-buffer))
  :config
  (counsel-mode 1))

(use-package marginalia
  :init
  (marginalia-mode))

(use-package corfu
    :ensure t
    :init
    (global-corfu-mode)  ; Enable globally
    (setq corfu-auto t)  ; Enable auto completion
    (setq corfu-cycle t)
    (setq corfu-auto-prefix 2)
    (setq corfu-auto-delay 0.2)
    (setq corfu-quit-at-boundary t)  ; Quit completion at word boundary
    (setq corfu-quit-no-match 'separator)
    (setq corfu-popupinfo-delay 0.2)  ; Quick documentation popup
    :bind
    (:map corfu-map
          ("TAB" . corfu-next)
          ([tab] . corfu-next)
          ("S-TAB" . corfu-previous)
          ([backtab] . corfu-previous)
	  ("C-g" . corfu-quit)             ; Cancel popup with C-g
	  ("<escape>" . corfu-quit)))       ; Cancel popup with Esc

  ;;; Enable Corfu popupinfo for documentation
  (with-eval-after-load 'corfu
  (require 'corfu-popupinfo)
  (corfu-popupinfo-mode 1))

(defun cape-yasnippet ()
"Completion-at-point function for Yasnippet with prefix filtering."
(require 'yasnippet)
(when (and (bound-and-true-p yas-minor-mode)
           (yas--get-snippet-tables))
  (let ((start (max (point-min)
                    (save-excursion
                      (skip-chars-backward "[:word:]_-")
                      (point)))))
    (list start (point)
          (completion-table-dynamic
           (lambda (input)
             (let* ((table (yas--get-snippet-tables))
                    (snippets (mapcar #'yas--template-key
                                      (yas--all-templates table)))
                    (completion-list (cl-remove-if-not #'identity snippets)))
               (cl-remove-if-not
                (lambda (c) (string-prefix-p input c))
                completion-list))))
          :annotation-function (lambda (s) (concat " [YAS]"))
          :company-kind (lambda (_) 'snippet)
          :exclusive 'no))))

(use-package cape
:ensure t
:config
(require 'cape)
(defun my/setup-cape ()
  (let ((capfs
         (list #'cape-dabbrev
               #'cape-file
               #'cape-keyword
               #'cape-yasnippet)))
    (when (fboundp 'cape-symbol)
      (push #'cape-symbol capfs))
    (setq-local completion-at-point-functions capfs)))
:hook ((prog-mode . my/setup-cape)
       (org-mode . my/setup-cape)))

(electric-pair-mode 1)

(use-package lsp-mode
  :hook ((python-mode . lsp)
         (rust-mode   . lsp))
  :commands lsp
  :init
  (setq lsp-completion-provider :none)
  (setq lsp-pylsp-plugins-jedi-enabled t
      lsp-pylsp-plugins-rope-completion-enabled t))

(setq org-confirm-babel-evaluate nil)
;; Python setup
(setq python-shell-interpreter "python3")

;; LSP setup
(defvar my/org-src-fake-file "/tmp/org-src-buffer.py")

(with-eval-after-load 'lsp-mode
  (setq lsp-disabled-clients '(pyls-ms pyright)
        lsp-enabled-clients '(pylsp)
        lsp-auto-guess-root t ; fallback if project detection fails
        lsp-session-file (expand-file-name ".lsp-session-v1" user-emacs-directory))
  
  ;; Setup LSP for org src temp buffers
  (defun my/org-src--maybe-setup-lsp ()
    (when (and (eq major-mode 'python-mode)
               (not (bound-and-true-p lsp-mode)))
      ;; Set fixed fake file path to fool LSP
      (setq buffer-file-name my/org-src-fake-file)
      (lsp)))
  
  (defun my/org-src--cleanup-fake-file-name ()
    (when (equal buffer-file-name my/org-src-fake-file)
      (setq buffer-file-name nil)))
  
  (add-hook 'org-src-mode-hook #'my/org-src--maybe-setup-lsp)
  (add-hook 'org-src-mode-exit-hook #'my/org-src--cleanup-fake-file-name))
;; Jupyter for org-babel
(add-to-list 'load-path "~/.emacs.d/man_installed/emacs-jupyter")
(use-package jupyter
  :defer t
  :init
  (with-eval-after-load 'org
    (require 'ob-jupyter)
    (org-babel-do-load-languages
     'org-babel-load-languages
     '((emacs-lisp . t)
       (python . t)
       (jupyter . t))))
  :config
  (setq org-babel-default-header-args:jupyter-python
        '((:session . "py")
          (:kernel . "python3")
          (:exports . "both")
          (:results . "output"))))

;; .org to .ipynb
(add-to-list 'load-path "~/.emacs.d/man_installed/ox-ipynb/")
(require 'ox-ipynb)

(defun my/org-safe-jupyter-wrapper (orig-fn &rest args)
  "Only call jupyter-org functions if in Org mode."
  (if (derived-mode-p 'org-mode)
      (apply orig-fn args)
    ;; Otherwise do nothing (avoids crash in *Help*)
    nil))

(with-eval-after-load 'jupyter
  (advice-add 'jupyter-org--with-src-block-client :around #'my/org-safe-jupyter-wrapper))

(add-hook 'org-babel-after-execute-hook
          (lambda ()
            (when (derived-mode-p 'org-mode)
              (org-display-inline-images))))

(setq org-startup-with-inline-images t)

(use-package magit)

(use-package yasnippet
  :config
  (yas-global-mode 1))

(use-package yasnippet-snippets)

(use-package org)

(setq make-backup-files nil)
