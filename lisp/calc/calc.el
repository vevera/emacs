;;; calc.el --- the GNU Emacs calculator  -*- lexical-binding:t -*-

;; Copyright (C) 1990-1993, 2001-2025 Free Software Foundation, Inc.

;; Author: David Gillespie <daveg@synaptics.com>
;; Keywords: convenience, extensions

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Calc is split into many files.  This file is the main entry point.
;; This file includes autoload commands for various other basic Calc
;; facilities.  The more advanced features are based in calc-ext, which
;; in turn contains autoloads for the rest of the Calc files.  This
;; odd set of interactions is designed to make Calc's loading time
;; be as short as possible when only simple calculations are needed.

;; Original author's address:
;;  Dave Gillespie, daveg@synaptics.com, uunet!synaptx!daveg.
;;  Synaptics, Inc., 2698 Orchard Parkway, San Jose, CA 95134.
;;
;; The old address daveg@csvax.cs.caltech.edu will continue to
;; work for the foreseeable future.
;;
;; Bug reports and suggestions are always welcome!  (Type M-x
;; report-emacs-bug to send them).

;; All functions, macros, and Lisp variables defined here begin with one
;; of the prefixes "math", "Math", or "calc", with the exceptions of
;; "full-calc", "full-calc-keypad", "another-calc", "quick-calc",
;; and "defmath".  User-accessible variables begin with "var-".

;;; TODO:

;;   Fix rewrite mechanism to do less gratuitous rearrangement of terms.
;;   Implement a pattern-based "refers" predicate.
;;
;;   Make it possible to Undo a selection command.
;;   Figure out how to allow selecting rows of matrices.
;;   If cursor was in selection before, move it after j n, j p, j L, etc.
;;   Consider reimplementing calc-delete-selection using rewrites.
;;
;;   Implement line-breaking in non-flat compositions (is this desirable?).
;;   Implement matrix formatting with multi-line components.
;;
;;   Have "Z R" define a user command based on a set of rewrite rules.
;;   Support "incf" and "decf" in defmath definitions.
;;   Have defmath generate calls to calc-binary-op or calc-unary-op.
;;   Make some way to define algebraic functions using keyboard macros.
;;
;;   Allow calc-word-size=0 => Common Lisp-style signed bitwise arithmetic.
;;   Consider digamma function (and thus arb. prec. Euler's gamma constant).
;;   May as well make continued-fractions stuff available to the user.
;;
;;   How about matrix eigenvalues, SVD, pseudo-inverse, etc.?
;;   Should cache matrix inverses as well as decompositions.
;;   If dividing by a non-square matrix, use least-squares automatically.
;;   Consider supporting matrix exponentials.
;;
;;   Have ninteg detect and work around singularities at the endpoints.
;;   Use an adaptive subdivision algorithm for ninteg.
;;   Provide nsum and nprod to go along with ninteg.
;;
;;   Handle TeX-mode parsing of \matrix{ ... } where ... contains braces.
;;   Support AmS-TeX's \{d,t,}frac, \{d,t,}binom notations.
;;   Format and parse sums and products in Eqn and Math modes.
;;
;;   Get math-read-big-expr to read sums, products, etc.
;;   Change calc-grab-region to use math-read-big-expr.
;;   Have a way to define functions using := in Embedded Mode.
;;
;;   Support polar plotting with GNUPLOT.
;;   Make a calc-graph-histogram function.
;;
;;   Replace hokey formulas for complex functions with formulas designed
;;      to minimize roundoff while maintaining the proper branch cuts.
;;   Test accuracy of advanced math functions over whole complex plane.
;;   Extend Bessel functions to provide arbitrary precision.
;;   Extend advanced math functions to handle error forms and intervals.
;;   Provide a better implementation for math-sin-cos-raw.
;;   Provide a better implementation for math-hypot.
;;   Provide a better implementation for math-make-frac.
;;   Provide a better implementation for calcFunc-prfac.
;;   Provide a better implementation for calcFunc-factor.
;;
;;   Provide more examples in the tutorial section of the manual.
;;   Cover in the tutorial:  simplification modes, declarations,
;;       bitwise stuff, selections, matrix mapping, financial functions.
;;   Provide more Lisp programming examples in the manual.
;;   Finish the Internals section of the manual (and bring it up to date).
;;
;;   Tim suggests adding spreadsheet-like features.
;;   Implement language modes for Gnuplot, Lisp, Ada, APL, ...?
;;
;; For atan series, if x > tan(pi/12) (about 0.268) reduce using the identity
;;   atan(x) = atan((x * sqrt(3) - 1) / (sqrt(3) + x)) + pi/6.
;;
;; A better integration algorithm:
;;   Use breadth-first instead of depth-first search, as follows:
;;	The integral cache allows unfinished integrals in symbolic notation
;;	on the righthand side.  An entry with no unfinished integrals on the
;;	RHS is "complete"; references to it elsewhere are replaced by the
;;	integrated value.  More than one cache entry for the same integral
;;	may exist, though if one becomes complete, the others may be deleted.
;;	The integrator works by using every applicable rule (such as
;;	substitution, parts, linearity, etc.) to generate possible righthand
;;	sides, all of which are entered into the cache.  Now, as long as the
;;	target integral is not complete (and the time limit has not run out)
;;	choose an incomplete integral from the cache and, for every integral
;;	appearing in its RHS's, add those integrals to the cache using the
;;	same substitution, parts, etc. rules.  The cache should be organized
;;	as a priority queue, choosing the "simplest" incomplete integral at
;;	each step, or choosing randomly among equally simple integrals.
;;	Simplicity equals small size, and few steps removed from the original
;;	target integral.  Note that when the integrator finishes, incomplete
;;	integrals can be left in the cache, so the algorithm can start where
;;	it left off if another similar integral is later requested.
;;   Breadth-first search would avoid the nagging problem of, e.g., whether
;;   to use parts or substitution first, and which decomposition is best.
;;   All are tried, and any path that diverges will quickly be put on the
;;   back burner by the priority queue.
;;   Note: Probably a good idea to call math-simplify-extended before
;;   measuring a formula's simplicity.

;;; Code:

(require 'calc-macs)
(require 'rect)

;; Declare functions which are defined elsewhere.
(declare-function calc-set-language "calc-lang" (lang &optional option no-refresh))
(declare-function calc-edit-finish "calc-yank" (&optional keep))
(declare-function calc-edit-cancel "calc-yank" ())
(declare-function calc-locate-cursor-element "calc-yank" (pt))
(declare-function calc-do-quick-calc "calc-aent" (&optional insert))
(declare-function calc-do-calc-eval "calc-aent" (str separator args))
(declare-function calc-do-keypad "calc-keypd" (&optional full-display interactive))
(declare-function calcFunc-unixtime "calc-forms" (date &optional zone))
(declare-function math-parse-date "calc-forms" (math-pd-str))
(declare-function math-lessp "calc-ext" (a b))
(declare-function math-compare "calc-ext" (a b))
(declare-function math-zerop "calc-misc" (a))
(declare-function calc-embedded-finish-command "calc-embed" ())
(declare-function calc-embedded-select-buffer "calc-embed" ())
(declare-function calc-embedded-mode-line-change "calc-embed" ())
(declare-function calc-push-list-in-macro "calc-prog" (vals m sels))
(declare-function calc-replace-selections "calc-sel" (n vals m))
(declare-function calc-record-list "calc-misc" (vals &optional prefix))
(declare-function calc-normalize-fancy "calc-ext" (val))
(declare-function calc-do-handle-whys "calc-misc" ())
(declare-function calc-top-selected "calc-sel" (&optional n m))
(declare-function calc-sel-error "calc-sel" ())
(declare-function calc-pop-stack-in-macro "calc-prog" (n mm))
(declare-function calc-embedded-stack-change "calc-embed" ())
(declare-function calc-refresh-evaltos "calc-ext" (&optional which-var))
(declare-function calc-do-refresh "calc-misc" ())
(declare-function calc-binary-op-fancy "calc-ext" (name func arg ident unary))
(declare-function calc-unary-op-fancy "calc-ext" (name func arg))
(declare-function calc-delete-selection "calc-sel" (n))
(declare-function calc-alg-digit-entry "calc-aent" ())
(declare-function calc-alg-entry "calc-aent" (&optional initial prompt))
(declare-function calc-dots "calc-incom" ())
(declare-function calc-temp-minibuffer-message "calc-misc" (m))
(declare-function math-read-radix-digit "calc-misc" (dig))
(declare-function calc-digit-dots "calc-incom" ())
(declare-function math-normalize-fancy "calc-ext" (a))
(declare-function math-normalize-nonstandard "calc-ext" (a))
(declare-function math-recompile-eval-rules "calc-alg" ())
(declare-function math-apply-rewrites "calc-rewr" (expr rules &optional heads math-apply-rw-ruleset))
(declare-function calc-record-why "calc-misc" (&rest stuff))
(declare-function math-dimension-error "calc-vec" ())
(declare-function calc-incomplete-error "calc-incom" (a))
(declare-function math-float-fancy "calc-arith" (a))
(declare-function math-neg-fancy "calc-arith" (a))
(declare-function calc-add-fractions "calc-frac" (a b))
(declare-function math-add-objects-fancy "calc-arith" (a b))
(declare-function math-add-symb-fancy "calc-arith" (a b))
(declare-function math-mul-zero "calc-arith" (a b))
(declare-function calc-mul-fractions "calc-frac" (a b))
(declare-function math-mul-objects-fancy "calc-arith" (a b))
(declare-function math-mul-symb-fancy "calc-arith" (a b))
(declare-function math-reject-arg "calc-misc" (&optional a p option))
(declare-function math-div-by-zero "calc-arith" (a b))
(declare-function math-div-zero "calc-arith" (a b))
(declare-function math-make-frac "calc-frac" (num den))
(declare-function calc-div-fractions "calc-frac" (a b))
(declare-function math-div-objects-fancy "calc-arith" (a b))
(declare-function math-div-symb-fancy "calc-arith" (a b))
(declare-function math-compose-expr "calccomp" (a prec &optional div))
(declare-function math-comp-width "calccomp" (c))
(declare-function math-composition-to-string "calccomp" (c &optional width))
(declare-function math-stack-value-offset-fancy "calccomp" (c))
(declare-function math-format-flat-expr-fancy "calc-ext" (a prec))
(declare-function math-adjust-fraction "calc-ext" (a))
(declare-function math-format-binary "calc-bin" (a))
(declare-function math-format-radix "calc-bin" (a))
(declare-function math-format-twos-complement "calc-bin" (a))
(declare-function math-group-float "calc-ext" (str))
(declare-function math-mod "calc-misc" (a b))
(declare-function math-format-number-fancy "calc-ext" (a prec))
(declare-function math-read-number-fancy "calc-ext" (s))
(declare-function calc-do-grab-region "calc-yank" (top bot arg))
(declare-function calc-do-grab-rectangle "calc-yank" (top bot arg &optional reduce))
(declare-function calc-do-embedded "calc-embed" (calc-embed-arg end obeg oend))
(declare-function calc-do-embedded-activate "calc-embed" (calc-embed-arg cbuf))
(declare-function math-do-defmath "calc-prog" (func args body))
(declare-function calc-load-everything "calc-ext" ())


(defgroup calc nil
  "Advanced desk calculator and mathematical tool."
  :prefix "calc-"
  :tag    "Calc"
  :group  'applications)

;; Do not autoload, so it is evaluated at run-time rather than at dump time.
;; ;;;###autoload
(defcustom calc-settings-file
  (locate-user-emacs-file "calc.el" ".calc.el")
  "File in which to record permanent settings."
  :type '(file))

(defcustom calc-language-alist
  '((latex-mode . latex)
    (tex-mode   . tex)
    (plain-tex-mode . tex)
    (context-mode . tex)
    (nroff-mode . eqn)
    (pascal-mode . pascal)
    (c-mode . c)
    (c++-mode . c)
    (fortran-mode . fortran)
    (f90-mode . fortran)
    (texinfo-mode . calc-normal-language))
  "Alist of major modes with appropriate Calc languages."
  :type '(alist :key-type (symbol :tag "Major mode")
                :value-type (symbol :tag "Calc language")))

(defcustom calc-embedded-announce-formula
  "%Embed\n\\(% .*\n\\)*"
  "A regular expression which is sure to be followed by a `calc-embedded' formula."
  :type '(regexp))

(defcustom calc-embedded-announce-formula-alist
  '((c++-mode     . "//Embed\n\\(// .*\n\\)*")
    (c-mode       . "/\\*Embed\\*/\n\\(/\\* .*\\*/\n\\)*")
    (f90-mode     . "!Embed\n\\(! .*\n\\)*")
    (fortran-mode . "C Embed\n\\(C .*\n\\)*")
    (html-helper-mode . "<!-- Embed -->\n\\(<!-- .* -->\n\\)*")
    (html-mode    . "<!-- Embed -->\n\\(<!-- .* -->\n\\)*")
    (nroff-mode   . "\\\\\"Embed\n\\(\\\\\" .*\n\\)*")
    (pascal-mode  . "{Embed}\n\\({.*}\n\\)*")
    (sgml-mode    . "<!-- Embed -->\n\\(<!-- .* -->\n\\)*")
    (xml-mode     . "<!-- Embed -->\n\\(<!-- .* -->\n\\)*")
    (texinfo-mode . "@c Embed\n\\(@c .*\n\\)*"))
  "Alist of major modes for `calc-embedded-announce-formula'."
  :type '(alist :key-type (symbol :tag "Major mode")
                :value-type (regexp :tag "Regexp to announce formula")))

(defcustom calc-embedded-open-formula
  "\\`\\|^\n\\|\\$\\$?\\|\\\\\\[\\|^\\\\begin[^{].*\n\\|^\\\\begin{.*[^x]}.*\n\\|^@.*\n\\|^\\.EQ.*\n\\|\\\\(\\|^%\n\\|^\\.\\\\\"\n"
  "Regexp for the opening delimiter of a formula used by `calc-embedded'."
  :type '(regexp))

(defcustom calc-embedded-close-formula
  "\\'\\|\n$\\|\\$\\$?\\|\\\\]\\|^\\\\end[^{].*\n\\|^\\\\end{.*[^x]}.*\n\\|^@.*\n\\|^\\.EN.*\n\\|\\\\)\\|\n%\n\\|^\\.\\\\\"\n"
  "Regexp for the closing delimiter of a formula used by `calc-embedded'."
  :type '(regexp))

(defcustom calc-embedded-open-close-formula-alist
  nil
  "Alist of major modes with pairs of formula delimiters used by `calc-embedded'."
  :type '(alist :key-type (symbol :tag "Major mode")
                :value-type (list (regexp :tag "Opening formula delimiter")
                                  (regexp :tag "Closing formula delimiter"))))

(defcustom calc-embedded-word-regexp
  "[-+]?[0-9]+\\(\\.[0-9]+\\)?\\([eE][-+]?[0-9]+\\)?"
  "A regular expression determining a word for calc-embedded-word."
  :type '(regexp))

(defcustom calc-embedded-word-regexp-alist
  nil
  "Alist of major modes with word regexps used by calc-embedded-word."
  :type '(alist :key-type (symbol :tag "Major mode")
                :value-type (regexp :tag "Regexp for word")))

(defcustom calc-embedded-open-plain
  "%%% "
  "A string which is the opening delimiter for a \"plain\" formula.
If calc-show-plain mode is enabled, this is inserted at the front of
each formula."
  :type '(string))

(defcustom calc-embedded-close-plain
  " %%%\n"
  "A string which is the closing delimiter for a \"plain\" formula.
See calc-embedded-open-plain."
  :type '(string))

(defcustom calc-embedded-open-close-plain-alist
  '((c++-mode     "// %% "   " %%\n")
    (c-mode       "/* %% "   " %% */\n")
    (f90-mode     "! %% "    " %%\n")
    (fortran-mode "C %% "    " %%\n")
    (html-helper-mode "<!-- %% " " %% -->\n")
    (html-mode "<!-- %% " " %% -->\n")
    (nroff-mode   "\\\" %% " " %%\n")
    (pascal-mode  "{%% "    " %%}\n")
    (sgml-mode     "<!-- %% " " %% -->\n")
    (xml-mode     "<!-- %% " " %% -->\n")
    (texinfo-mode "@c %% "   " %%\n"))
  "Alist of major modes with pairs of delimiters for \"plain\" formulas."
  :type '(alist :key-type (symbol :tag "Major mode")
                :value-type (list (string :tag "Opening \"plain\" delimiter")
                                  (string :tag "Closing \"plain\" delimiter"))))

(defcustom calc-embedded-open-new-formula
  "\n\n"
  "A string which is inserted at front of formula by calc-embedded-new-formula."
  :type '(string))

(defcustom calc-embedded-close-new-formula
  "\n\n"
  "A string which is inserted at end of formula by calc-embedded-new-formula."
  :type '(string))

(defcustom calc-embedded-open-close-new-formula-alist
  nil
  "Alist of major modes with pairs of new formula delimiters used by calc-embedded."
  :type '(alist :key-type (symbol :tag "Major mode")
                :value-type (list (string :tag "Opening new formula delimiter")
                                  (string :tag "Closing new formula delimiter"))))

(defcustom calc-embedded-open-mode
  "% "
  "A string which should precede `calc-embedded' mode annotations.
This is not required to be present for user-written mode annotations."
  :type '(string))

(defcustom calc-embedded-close-mode
  "\n"
  "A string which should follow `calc-embedded' mode annotations.
This is not required to be present for user-written mode annotations."
  :type '(string))

(defcustom calc-embedded-open-close-mode-alist
  '((c++-mode     "// "   "\n")
    (c-mode       "/* "   " */\n")
    (f90-mode     "! "    "\n")
    (fortran-mode "C "    "\n")
    (html-helper-mode "<!-- " " -->\n")
    (html-mode    "<!-- " " -->\n")
    (nroff-mode   "\\\" " "\n")
    (pascal-mode  "{ "    " }\n")
    (sgml-mode    "<!-- " " -->\n")
    (xml-mode     "<!-- " " -->\n")
    (texinfo-mode "@c "   "\n"))
  "Alist of major modes with pairs of strings to delimit annotations."
  :type '(alist :key-type (symbol :tag "Major mode")
                :value-type (list (string :tag "Opening annotation delimiter")
                                  (string :tag "Closing annotation delimiter"))))

(defcustom calc-gnuplot-name
  (if (and (eq system-type 'windows-nt)
           ;; Gnuplot v4.x on MS-Windows came with a special
           ;; pipe-enabled gnuplot executable for batch-mode
           ;; execution; newer versions allow using gnuplot.exe.
           (executable-find "pgnuplot"))
      "pgnuplot"
    "gnuplot")
  "Name of GNUPLOT program, for calc-graph features."
  :type '(string)
  :version "26.2")

(defcustom calc-gnuplot-plot-command nil
  "Name of command for displaying GNUPLOT output; %s = file name to print."
  :type '(choice (string) (sexp)))

(defcustom calc-gnuplot-print-command "lp %s"
  "Name of command for printing GNUPLOT output; %s = file name to print."
  :type '(choice (string) (sexp)))

(defcustom calc-multiplication-has-precedence t
  "If non-nil, multiplication has precedence over division in normal mode."
  :type 'boolean)

(defcustom calc-ensure-consistent-units nil
  "If non-nil, ensure new units are consistent with current units when converting."
  :version "24.3"
  :type 'boolean)

(defcustom calc-context-sensitive-enter nil
  "If non-nil, the stack element under the cursor will be copied by `calc-enter'
and deleted by `calc-pop'."
  :version "24.4"
  :type 'boolean)

(defcustom calc-undo-length 100
  "The number of undo steps that will be preserved when Calc is quit."
  :type 'natnum)

(defcustom calc-highlight-selections-with-faces nil
  "If non-nil, use a separate face to indicate selected sub-formulas.
If option `calc-show-selections' is non-nil, then selected sub-formulas are
shown by displaying the rest of the formula in `calc-nonselected-face'.
If option `calc-show-selections' is nil, then selected sub-formulas are shown
by displaying the sub-formula in `calc-selected-face'."
  :version "24.1"
  :type 'boolean)

(defcustom calc-lu-field-reference "20 uPa"
  "The default reference level for logarithmic units (field)."
  :version "24.1"
  :type '(string))

(defcustom calc-lu-power-reference "mW"
  "The default reference level for logarithmic units (power)."
  :version "24.1"
  :type '(string))

(defcustom calc-note-threshold "1"
  "The number of cents that a frequency should be near a note
to be identified as that note."
  :version "24.1"
  :type 'string)

(defcustom calc-kill-line-numbering t
  "If non-nil, calculator kills include any line numbering.

This option does not affect calc kill and copy commands which
operate on the region, such as `calc-copy-region-as-kill'."
  :version "29.1"
  :type 'boolean)

(defvar math-format-date-cache) ; calc-forms.el

(defface calc-nonselected-face
  '((t :inherit shadow
       :slant italic))
  "Face used to show the non-selected portion of a formula.")

(defface calc-selected-face
  '((t :weight bold))
  "Face used to show the selected portion of a formula.")

(define-obsolete-variable-alias 'calc-bug-address 'report-emacs-bug-address
  "26.2")

(defvar calc-scan-for-dels t
  "If t, scan keymaps to find all DEL-like keys.
if nil, only DEL itself is mapped to calc-pop.")

(defvar calc-stack '((top-of-stack 1 nil))
  "Calculator stack.
Entries are 3-lists:  Formula, Height (in lines), Selection (or nil).")

(defvar calc-stack-top 1
  "Index into `calc-stack' of \"top\" of stack.
This is 1 unless `calc-truncate-stack' has been used.")

(defvar calc-display-sci-high 0
  "Floating-point numbers with this positive exponent or higher above the
current precision are displayed in scientific notation in `calc-mode'.")

(defvar calc-display-sci-low -3
  "Floating-point numbers with this negative exponent or lower are displayed
scientific notation in `calc-mode'.")

(defvar calc-digit-after-point nil
  "If t, display at least one digit after the decimal point, as in `12.0'.
If nil, the decimal point may come last in a number, as in `12.'.
This setting only applies to floats in normal display mode.")

(defvar calc-other-modes nil
  "List of used-defined strings to append to Calculator mode line.")

(defvar calc-Y-help-msgs nil
  "List of strings for Y prefix help.")

(defvar calc-loaded-settings-file nil
  "Return t if `calc-settings-file' has been loaded yet.")


(defvar calc-mode-var-list '()
  "List of variables used in customizing GNU Calc.")

(defmacro defcalcmodevar (var defval &optional doc)
  "Declare VAR as a Calc variable, with default value DEFVAL and doc-string DOC.
The variable VAR will be added to `calc-mode-var-list'."
  (declare (doc-string 3) (indent defun))
  `(progn
     (defvar ,var ,defval ,doc)
     (add-to-list 'calc-mode-var-list (list (quote ,var) ,defval))))

(defun calc-mode-var-list-restore-default-values ()
  "Restore the default values of the variables in `calc-mode-var-list'."
  (mapcar (lambda (v) (set (car v) (nth 1 v)))
          calc-mode-var-list))

(defun calc-mode-var-list-restore-saved-values ()
  "Restore the user-saved values of the variables in `calc-mode-var-list'."
  (let ((newvarlist '()))
    (save-excursion
      (let (pos
            (file (substitute-in-file-name calc-settings-file)))
        (when (and
               (file-regular-p file)
               (set-buffer (find-file-noselect file))
               (goto-char (point-min))
               (search-forward ";;; Mode settings stored by Calc" nil t)
               (progn
                 (forward-line 1)
                 (setq pos (point))
                 (search-forward "\n;;; End of mode settings" nil t)))
          (beginning-of-line)
          (calc-mode-var-list-restore-default-values)
          (eval-region pos (point))
          (let ((varlist calc-mode-var-list))
            (while varlist
              (let ((var (car varlist)))
                (setq newvarlist
                      (cons (list (car var) (symbol-value (car var)))
                            newvarlist)))
              (setq varlist (cdr varlist)))))))
    (if newvarlist
        (mapcar (lambda (v) (set (car v) (nth 1 v)))
                newvarlist)
      (calc-mode-var-list-restore-default-values))))

(defcalcmodevar calc-always-load-extensions nil
  "If non-nil, load the calc-ext module automatically when Calc is loaded.")

(defcalcmodevar  calc-line-numbering t
  "If non-nil, display line numbers in Calculator stack.")

(defcalcmodevar calc-line-breaking t
  "If non-nil, break long values across multiple lines in Calculator stack.")

(defcalcmodevar calc-display-just nil
  "If nil, stack display is left-justified.
If `right', stack display is right-justified.
If `center', stack display is centered.")

(defcalcmodevar calc-display-origin nil
  "Horizontal origin of displayed stack entries.
In left-justified mode, this is effectively indentation.  (Default 0).
In right-justified mode, this is effectively window width.
In centered mode, center of stack entry is placed here.")

(defcalcmodevar calc-number-radix 10
  "Radix for entry and display of numbers in calc-mode, 2-36.")

(defcalcmodevar calc-leading-zeros nil
  "If non-nil, leading zeros are provided to pad integers to calc-word-size.")

(defcalcmodevar calc-group-digits nil
  "If non-nil, group digits in large displayed integers by inserting spaces.
If an integer, group that many digits at a time.
If t, use 4 for binary and hex, 3 otherwise.")

(defcalcmodevar calc-group-char ","
  "The character (in the form of a string) to be used for grouping digits.
This is used only when calc-group-digits mode is on.")

(defcalcmodevar calc-point-char "."
  "The character (in the form of a string) to be used as a decimal point.")

(defcalcmodevar calc-frac-format '(":" nil)
  "Format of displayed fractions; a string of one or two of \":\" or \"/\".")

(defcalcmodevar calc-prefer-frac nil
  "If non-nil, prefer fractional over floating-point results.")

(defcalcmodevar calc-hms-format "%s@ %s' %s\""
  "Format of displayed hours-minutes-seconds angles, a format string.
String must contain three %s marks for hours, minutes, seconds respectively.")

(defcalcmodevar calc-date-format '((H ":" mm C SS pp " ")
                                  Www " " Mmm " " D ", " YYYY)
  "Format of displayed date forms.")

(defcalcmodevar calc-float-format '(float 0)
  "Format to use for display of floating-point numbers in calc-mode.
Must be a list of one of the following forms:
 (float 0)      Floating point format, display full precision.
 (float N)      N > 0: Floating point format, at most N significant figures.
 (float -N)     -N < 0: Floating point format, calc-internal-prec - N figs.
 (fix N)        N >= 0: Fixed point format, N places after decimal point.
 (sci 0)        Scientific notation, full precision.
 (sci N)        N > 0: Scientific notation, N significant figures.
 (sci -N)       -N < 0: Scientific notation, calc-internal-prec - N figs.
 (eng 0)        Engineering notation, full precision.
 (eng N)        N > 0: Engineering notation, N significant figures.
 (eng -N)       -N < 0: Engineering notation, calc-internal-prec - N figs.")

(defcalcmodevar calc-full-float-format '(float 0)
  "Format to use when full precision must be displayed.")

(defcalcmodevar calc-complex-format nil
  "Format to use for display of complex numbers in calc-mode.  Must be one of:
  nil            Use (x, y) form.
  i              Use x + yi form.
  j              Use x + yj form.")

(defcalcmodevar calc-complex-mode 'cplx
  "Preferred form, either `cplx' or `polar', for complex numbers.")

(defcalcmodevar calc-infinite-mode nil
  "If nil, 1 / 0 is left unsimplified.
If 0, 1 / 0 is changed to inf (zeros are considered positive).
Otherwise, 1 / 0 is changed to uinf (undirected infinity).")

(defcalcmodevar calc-display-strings nil
  "If non-nil, display vectors of byte-sized integers as strings.")

(defcustom calc-string-maximum-character #xFF
  "Maximum value of vector contents to be displayed as a string.

If a vector consists of characters up to this maximum value, the
function `calc-display-strings' will toggle displaying the vector as a
string.  This maximum value must represent a character (see `characterp').
Some natural choices (and their resulting ranges) are:

- `0x7F'     (`ASCII'),
- `0xFF'     (`Latin-1', the default),
- `0x10FFFF' (`Unicode'),
- `0x3FFFFF' (`Emacs').

Characters for low control codes are either caret or backslash escaped,
while others without a glyph are displayed in backslash-octal notation.
The display of strings containing higher character codes will depend on
your display settings and system font coverage.

See the following for further information:

- info node `(calc)Strings',
- info node `(elisp)Text Representations',
- info node `(emacs)Text Display'."
  :version "31.1"
  :type '(choice (restricted-sexp :tag "Character Code"
                                  :match-alternatives (characterp))
                 (const :tag "ASCII"   #x7F)
                 (const :tag "Latin-1" #xFF)
                 (const :tag "Unicode" #x10FFFF)
                 (const :tag "Emacs"   #x3FFFFF)))

(defcalcmodevar calc-matrix-just 'center
  "If nil, vector elements are left-justified.
If `right', vector elements are right-justified.
If `center', vector elements are centered.")

(defcalcmodevar calc-break-vectors nil
  "If non-nil, display vectors one element per line.")

(defcalcmodevar calc-full-vectors t
  "If non-nil, display long vectors in full.  If nil, use abbreviated form.")

(defcalcmodevar calc-full-trail-vectors t
  "If non-nil, display long vectors in full in the trail.")

(defcalcmodevar calc-vector-commas ","
  "If non-nil, separate elements of displayed vectors with this string.")

(defcalcmodevar calc-vector-brackets "[]"
  "If non-nil, surround displayed vectors with these characters.")

(defcalcmodevar calc-matrix-brackets '(R O)
  "A list of code-letter symbols that control \"big\" matrix display.
If `R' is present, display inner brackets for matrices.
If `O' is present, display outer brackets for matrices (above/below).
If `C' is present, display outer brackets for matrices (centered).")

(defcalcmodevar calc-language nil
  "Language or format for entry and display of stack values.  Must be one of:
  nil		Use standard Calc notation.
  flat		Use standard Calc notation, one-line format.
  big		Display formulas in 2-d notation (enter w/std notation).
  unform	Use unformatted display: add(a, mul(b,c)).
  c		Use C language notation.
  pascal	Use Pascal language notation.
  fortran	Use Fortran language notation.
  tex		Use TeX notation.
  latex         Use LaTeX notation.
  eqn		Use eqn notation.
  yacas         Use Yacas notation.
  maxima        Use Maxima notation.
  giac          Use Giac notation.
  math		Use Mathematica(tm) notation.
  maple		Use Maple notation.")

(defcalcmodevar calc-language-option nil
  "Numeric prefix argument for the command that set `calc-language'.")

(defcalcmodevar calc-left-label ""
  "Label to display at left of formula.")

(defcalcmodevar calc-right-label ""
  "Label to display at right of formula.")

(defcalcmodevar calc-word-size 32
  "Minimum number of bits per word, if any, for binary operations in calc-mode.")

(defcalcmodevar calc-previous-modulo nil
  "Most recently used value of M in a modulo form.")

(defcalcmodevar calc-simplify-mode 'alg
  "Type of simplification applied to results.
If `none', results are not simplified when pushed on the stack.
If `num', functions are simplified only when args are constant.
If nil, only limited simplifications are applied.
If `binary', `math-clip' is applied if appropriate.
If `alg', `math-simplify' is applied.
If `ext', `math-simplify-extended' is applied.
If `units', `math-simplify-units' is applied.")

(defcalcmodevar calc-auto-recompute t
  "If non-nil, recompute evalto's automatically when necessary.")

(defcalcmodevar calc-display-raw nil
  "If non-nil, display shows unformatted Lisp exprs. (For debugging)")

(defcalcmodevar calc-internal-prec 12
  "Number of digits of internal precision for calc-mode calculations.")

(defcalcmodevar calc-angle-mode 'deg
  "If deg, angles are in degrees; if rad, angles are in radians.
If hms, angles are in degrees-minutes-seconds.")

(defcalcmodevar calc-algebraic-mode nil
  "If non-nil, numeric entry accepts whole algebraic expressions.
If nil, algebraic expressions must be preceded by \"\\='\".")

(defcalcmodevar calc-incomplete-algebraic-mode nil
  "Like calc-algebraic-mode except only affects ( and [ keys.")

(defcalcmodevar calc-symbolic-mode nil
  "If non-nil, inexact numeric computations like sqrt(2) are postponed.
If nil, computations on numbers always yield numbers where possible.")

(defcalcmodevar calc-matrix-mode nil
  "If `matrix', variables are assumed to be matrix-valued.
If a number, variables are assumed to be NxN matrices.
If `sqmatrix', variables are assumed to be square matrices of an
  unspecified size.
If `scalar', variables are assumed to be scalar-valued.
If nil, symbolic math routines make no assumptions about variables.")

(defcalcmodevar calc-twos-complement-mode nil
  "If non-nil, display integers in two's complement mode.")


(defcalcmodevar calc-shift-prefix nil
  "If non-nil, shifted letter keys are prefix keys rather than normal meanings.")

(defcalcmodevar calc-window-height 7
  "Initial height of Calculator window.")

(defcalcmodevar calc-display-trail t
  "If non-nil, \\[calc] creates a window to display Calculator trail.")

(defcalcmodevar calc-show-selections t
  "If non-nil, selected sub-formulas are shown by obscuring rest of formula.
If nil, selected sub-formulas are highlighted by obscuring the sub-formulas.")

(defcalcmodevar calc-use-selections t
  "If non-nil, commands operate only on selected portions of formulas.
If nil, selections displayed but ignored.")

(defcalcmodevar calc-assoc-selections t
  "If non-nil, selection hides deep structure of associative formulas.")

(defcalcmodevar calc-display-working-message 'lots
  "If non-nil, display \"Working...\" for potentially slow Calculator commands.")

(defcalcmodevar calc-auto-why 'maybe
  "If non-nil, automatically execute a \"why\" command to explain odd results.")

(defcalcmodevar calc-timing nil
  "If non-nil, display timing information on each slow command.")

(defcalcmodevar calc-mode-save-mode 'local)

(defcalcmodevar calc-standard-date-formats
  '("N"
    "<H:mm:SSpp >Www Mmm D, YYYY"
    "D Mmm YYYY<, h:mm:SS>"
    "Www Mmm BD< hh:mm:ss> YYYY"
    "M/D/Y< H:mm:SSpp>"
    "D.M.Y< h:mm:SS>"
    "M-D-Y< H:mm:SSpp>"
    "D-M-Y< h:mm:SS>"
    "j<, h:mm:SS>"
    "YYddd< hh:mm:ss>"
    "ZYYY-MM-DD Www< hh:mm>"
    "IYYY-Iww-w<Thh:mm:ss>"))

(defcalcmodevar calc-autorange-units nil
  "If non-nil, automatically set unit prefixes to keep units in a reasonable range.")

(defcalcmodevar calc-was-keypad-mode nil
  "Non-nil if Calc was last invoked in keypad mode.")

(defcalcmodevar calc-full-mode nil
  "Non-nil if Calc was last invoked in full-screen mode.")

(defcalcmodevar calc-user-parse-tables nil
  "Alist of languages with user-defined parse rules.")

(defcalcmodevar calc-gnuplot-default-device "default"
  "The default device name for GNUPLOT plotting.")

(defcalcmodevar calc-gnuplot-default-output "STDOUT"
  "The default output file for GNUPLOT plotting.")

(defcalcmodevar calc-gnuplot-print-device "postscript"
  "The default device name for GNUPLOT printing.")

(defcalcmodevar calc-gnuplot-print-output "auto"
  "The default output for GNUPLOT printing.")

(defcalcmodevar calc-gnuplot-geometry nil
  "The default geometry for the GNUPLOT window.")

(defcalcmodevar calc-graph-default-resolution 15
  "The default number of data points when plotting curves.")

(defcalcmodevar calc-graph-default-resolution-3d 5
  "The default number of x- and y- data points when plotting surfaces.")

(defcalcmodevar calc-invocation-macro nil
  "A user defined macro for starting Calc.
Used by `calc-user-invocation'.")

(defcalcmodevar calc-show-banner t
  "If non-nil, show a friendly greeting above the stack.")

(defconst calc-local-var-list '(calc-stack
				calc-stack-top
				calc-undo-list
				calc-redo-list
				calc-always-load-extensions
				calc-mode-save-mode
				calc-display-raw
				calc-line-numbering
				calc-line-breaking
				calc-display-just
				calc-display-origin
				calc-left-label
				calc-right-label
				calc-auto-why
				calc-algebraic-mode
				calc-incomplete-algebraic-mode
				calc-symbolic-mode
				calc-matrix-mode
				calc-inverse-flag
				calc-hyperbolic-flag
                                calc-option-flag
				calc-keep-args-flag
				calc-angle-mode
				calc-number-radix
				calc-leading-zeros
				calc-group-digits
				calc-group-char
				calc-point-char
				calc-frac-format
				calc-prefer-frac
				calc-hms-format
				calc-date-format
				calc-standard-date-formats
				calc-float-format
				calc-full-float-format
				calc-complex-format
				calc-matrix-just
				calc-full-vectors
				calc-full-trail-vectors
				calc-break-vectors
				calc-vector-commas
				calc-vector-brackets
				calc-matrix-brackets
				calc-complex-mode
				calc-infinite-mode
				calc-display-strings
				calc-simplify-mode
				calc-auto-recompute
				calc-autorange-units
				calc-show-plain
				calc-show-selections
				calc-use-selections
				calc-assoc-selections
				calc-word-size
				calc-internal-prec))

(defvar calc-mode-hook nil
  "Hook run when entering calc-mode.")

(defvar calc-trail-mode-hook nil
  "Hook run when entering calc-trail-mode.")

(defvar calc-start-hook nil
  "Hook run when calc is started.")

(defvar calc-end-hook nil
  "Hook run when calc is quit.")

(defvar calc-load-hook nil
  "Hook run when calc.el is loaded.")
(make-obsolete-variable 'calc-load-hook
                        "use `with-eval-after-load' instead." "28.1")

(defvar calc-window-hook nil
  "Hook called to create the Calc window.")

(defvar calc-trail-window-hook nil
  "Hook called to create the Calc trail window.")

(defvar calc-embedded-new-buffer-hook nil
  "Hook run when starting embedded mode in a new buffer.")

(defvar calc-embedded-new-formula-hook nil
  "Hook run when starting embedded mode in a new formula.")

(defvar calc-embedded-mode-hook nil
  "Hook run when starting embedded mode.")

(defvar calc-eval-error)

;; The following modes use specially-formatted data.
(put 'calc-mode 'mode-class 'special)

(define-error 'calc-error "Calc internal error")
(define-error 'inexact-result
  "Calc internal error (inexact-result)" 'calc-error)

(define-error 'math-overflow "Floating-point overflow occurred" 'calc-error)
(define-error 'math-underflow "Floating-point underflow occurred" 'calc-error)

(defvar calc-trail-pointer nil
  "The \"current\" entry in trail buffer.")
(defvar calc-trail-overlay nil
  "The value of `overlay-arrow-string'.")
(defvar calc-undo-list nil
  "The list of previous operations for undo.")
(defvar calc-redo-list nil
  "The list of recent undo operations.")
(defvar calc-main-buffer nil
  "A pointer to Calculator buffer.")
(defvar calc-buffer-list nil
  "A list of all Calc buffers.")
(defvar calc-trail-buffer nil
  "A pointer to Calc Trail buffer.")
(defvar calc-why nil
  "Explanations of most recent errors.")
(defvar calc-next-why nil)
(defvar calc-inverse-flag nil
  "If non-nil, next operation is Inverse.")
(defvar calc-hyperbolic-flag nil
  "If non-nil, next operation is Hyperbolic.")
(defvar calc-option-flag nil
  "If non-nil, next operation has Optional behavior.")
(defvar calc-keep-args-flag nil
  "If non-nil, next operation should not remove its arguments from stack.")
(defvar calc-function-open "("
  "Open-parenthesis string for function call notation.")
(defvar calc-function-close ")"
  "Close-parenthesis string for function call notation.")
(defvar calc-language-output-filter nil
  "Function through which to pass strings after formatting.")
(defvar calc-language-input-filter nil
  "Function through which to pass strings before parsing.")
(defvar calc-radix-formatter nil
  "Formatting function used for non-decimal numbers.")
(defvar calc-lang-slash-idiv nil
  "A list of languages in which / might represent integer division.")
(defvar calc-lang-allow-underscores nil
  "A list of languages which allow underscores in variable names.")
(defvar calc-lang-allow-percentsigns nil
  "A list of languages which allow percent signs in variable names.")
(defvar calc-lang-c-type-hex nil
  "Languages in which octal and hex numbers are written with leading 0 and 0x.")
(defvar calc-lang-brackets-are-subscripts nil
  "Languages in which subscripts are indicated by brackets.")
(defvar calc-lang-parens-are-subscripts nil
  "Languages in which subscripts are indicated by parentheses.")

(defvar calc-last-kill nil
  "The last number killed in calc-mode.")
(defvar calc-dollar-values nil
  "Values to be used for `$'.")
(defvar calc-dollar-used nil
  "The highest order of `$' that occurred.")
(defvar calc-hashes-used nil
  "The highest order of `#' that occurred.")
(defvar calc-quick-prev-results nil
  "Previous results from Quick Calc.")
(defvar calc-said-hello nil
  "Non-nil if the welcome message has been displayed.")
(defvar calc-executing-macro nil
  "Non-nil if a keyboard macro is executing from the \"K\" key.")
(defvar calc-any-selections nil
  "Non-nil if there are selections present.")
(defvar calc-help-phase 0
  "The number of consecutive \"?\" keystrokes.")
(defvar calc-full-help-flag nil
  "Non-nil if `calc-full-help' is being executed.")
(defvar calc-refresh-count 0
  "The number of `calc-refresh' calls.")
(defvar calc-display-dirty nil
  "Non-nil if the stack display might not reflect the latest mode settings.")
(defvar calc-prepared-composition nil)
(defvar calc-selection-cache-default-entry nil)
(defvar calc-embedded-info nil
  "If non-nil, a vector consisting of information for embedded mode.")
(defvar calc-embedded-active nil
  "Alist of buffers with sorted lists of calc-embedded-infos.")
(defvar calc-standalone-flag nil
  "Non-nil if Emacs started with standalone Calc.")
(defvar var-EvalRules nil
  "User defined rules that Calc will apply automatically.")
(defvar math-eval-rules-cache-tag t)
(defvar math-radix-explicit-format t)
(defvar math-expr-function-mapping nil
  "Alist of language specific functions with Calc functions.")
(defvar math-expr-variable-mapping nil
  "Alist of language specific variables with Calc variables.")
(defvar math-read-expr-quotes nil)
(defvar math-working-step nil)
(defvar math-working-step-2 nil)
(defvar var-i '(special-const (math-imaginary 1)))
(defvar var-pi '(special-const (math-pi)))
(defvar var-π '(special-const (math-pi)))
(defvar var-e '(special-const (math-e)))
(defvar var-phi '(special-const (math-phi)))
(defvar var-φ '(special-const (math-phi)))
(defvar var-gamma '(special-const (math-gamma-const)))
(defvar var-γ '(special-const (math-gamma-const)))
(defvar var-Modes '(special-const (math-get-modes-vec)))

(mapc (lambda (v) (or (boundp v) (set v nil)))
      calc-local-var-list)

(defvar calc-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map t)
    (define-key map "+" 'calc-plus)
    (define-key map "-" 'calc-minus)
    (define-key map "*" 'calc-times)
    (define-key map "/" 'calc-divide)
    (define-key map "%" 'calc-mod)
    (define-key map "&" 'calc-inv)
    (define-key map "^" 'calc-power)
    (define-key map "\M-%" 'calc-percent)
    (define-key map "e" 'calcDigit-start)
    (define-key map "i" 'calc-info)
    (define-key map "n" 'calc-change-sign)
    (define-key map "q" 'calc-quit)
    (define-key map "Y" 'nil)
    (define-key map "Y?" 'calc-shift-Y-prefix-help)
    (define-key map "?" 'calc-help)
    (define-key map " " 'calc-enter)
    (define-key map "'" 'calc-algebraic-entry)
    (define-key map "$" 'calc-auto-algebraic-entry)
    (define-key map "\"" 'calc-auto-algebraic-entry)
    (define-key map "\t" 'calc-roll-down)
    (define-key map "\M-\t" 'calc-roll-up)
    (define-key map "\C-x\C-t" 'calc-transpose-lines)
    (define-key map "\C-m" 'calc-enter)
    (define-key map "\M-\C-m" 'calc-last-args-stub)
    (define-key map "\C-j" 'calc-over)
    (define-key map "\C-y" 'calc-yank)
    (define-key map [mouse-2] 'calc-yank)
    (define-key map [remap undo] 'calc-undo)

    (mapc (lambda (x) (define-key map (char-to-string x) 'undefined))
          "lOW")
    (mapc (lambda (x) (define-key map (char-to-string x) 'calc-missing-key))
          (concat "ABCDEFGHIJKLMNOPQRSTUVXZabcdfghjkmoprstuvwxyz"
                  ":\\|!()[]<>{},;=~`\C-k\C-w"))
    (define-key map "\M-w" 'calc-missing-key)
    (define-key map "\M-k" 'calc-missing-key)
    (define-key map "\M-\C-w" 'calc-missing-key)
    (mapc (lambda (x) (define-key map (char-to-string x) 'calcDigit-start))
          "_0123456789.#@")
    map)
  "The key map for Calc.")

(defvar calc-digit-map
  (let ((map (make-keymap)))
    (map-keymap (lambda (key bind)
                  (define-key map (vector key)
                    (if (eq bind 'undefined)
                        'undefined 'calcDigit-nondigit)))
                calc-mode-map)
    (mapc (lambda (x) (define-key map (char-to-string x) 'calcDigit-key))
          "_0123456789.e+-:n#@oh'\"mspM")
    (mapc (lambda (x) (define-key map (char-to-string x) 'calcDigit-letter))
          "abcdfgijklqrtuvwxyzABCDEFGHIJKLNOPQRSTUVWXYZ")
    (define-key map "'" 'calcDigit-algebraic)
    (define-key map "`" 'calcDigit-edit)
    (define-key map "\C-g" 'abort-recursive-edit)
    map)
  "The key map for entering Calc digits.")

(mapc (lambda (x)
	(ignore-errors
          (define-key calc-digit-map x 'calcDigit-backspace)
          (define-key calc-mode-map x 'calc-pop)
          (define-key calc-mode-map (vconcat "\e" x) 'calc-pop-above)))
      (if calc-scan-for-dels
	  (append (where-is-internal 'delete-backward-char global-map)
		  (where-is-internal 'backward-delete-char global-map)
		  (where-is-internal 'backward-delete-char-untabify global-map)
		  '("\177"))
	'("\177")))

(mapc (lambda (x)
        (ignore-errors
          (define-key calc-digit-map x 'calcDigit-delchar)
          (define-key calc-mode-map x 'calc-pop)
          (define-key calc-mode-map (vconcat "\e" x) 'calc-pop-above)))
      (if calc-scan-for-dels
          (append (where-is-internal 'delete-forward-char global-map)
                  '("\C-d"))
        '("\C-d")))

(defvar calc-dispatch-map
  (let ((map (make-keymap)))
    (mapc (lambda (x)
	    (let* ((x-chr (car x))
		   (x-str (char-to-string x-chr))
		   (x-def (cdr x)))
	      (define-key map x-str x-def)
	      (when (string-match "[a-z]" x-str)
		;; Map upper case char to same definition.
		(define-key map (upcase x-str) x-def)
		(unless (string-match "[gmv]" x-str)
		  ;; Map control prefixed char to same definition.
		  (define-key map (vector (list 'control x-chr)) x-def)))
	      (define-key map (format "\e%c" x-chr) x-def)))
          '( ( ?a . calc-embedded-activate )
             ( ?b . calc-big-or-small )
             ( ?c . calc )
             ( ?d . calc-embedded-duplicate )
             ( ?e . calc-embedded )
             ( ?f . calc-embedded-new-formula )
             ( ?g . calc-grab-region )
             ( ?h . calc-dispatch-help )
             ( ?i . calc-info )
             ( ?j . calc-embedded-select )
             ( ?k . calc-keypad )
             ( ?l . calc-load-everything )
             ( ?m . read-kbd-macro )
             ( ?n . calc-embedded-next )
             ( ?o . calc-other-window )
             ( ?p . calc-embedded-previous )
             ( ?q . quick-calc )
             ( ?r . calc-grab-rectangle )
             ( ?s . calc-info-summary )
             ( ?t . calc-tutorial )
             ( ?u . calc-embedded-update-formula )
             ( ?w . calc-embedded-word )
             ( ?x . calc-quit )
             ( ?y . calc-copy-to-buffer )
             ( ?z . calc-user-invocation )
             ( ?\' . calc-embedded-new-formula )
             ( ?\` . calc-embedded-edit )
             ( ?: . calc-grab-sum-down )
             ( ?_ . calc-grab-sum-across )
             ( ?0 . calc-reset )
             ( ?? . calc-dispatch-help )
             ( ?# . calc-same-interface )
             ( ?& . calc-same-interface )
             ( ?\\ . calc-same-interface )
             ( ?= . calc-same-interface )
             ( ?* . calc-same-interface )
             ( ?/ . calc-same-interface )
             ( ?+ . calc-same-interface )
             ( ?- . calc-same-interface ) ))
    map)
  "The key map for starting Calc.")


;;;; (Autoloads here)
(load "calc-loaddefs" nil t)

;;;###autoload (define-key ctl-x-map "*" 'calc-dispatch)

;;;###autoload
(defun calc-dispatch (&optional _arg)
  "Invoke the GNU Emacs Calculator.  See \\[calc-dispatch-help] for details."
  (interactive)
;  (sit-for echo-keystrokes)
  (ignore-errors                   ; look for other keys bound to calc-dispatch
    (let ((keys (this-command-keys)))
      (unless (or (not (stringp keys))
                  (string-match "\\`\C-u\\|\\`\e[-0-9#]\\|`[\M--\M-0-\M-9]" keys)
                  (eq (lookup-key calc-dispatch-map keys) 'calc-same-interface))
        (when (and (string-match "\\`[\C-@-\C-_]" keys)
                   (symbolp
                    (lookup-key calc-dispatch-map (substring keys 0 1))))
          (define-key calc-dispatch-map (substring keys 0 1) nil))
        (define-key calc-dispatch-map keys 'calc-same-interface))))
  (calc-do-dispatch))

(defvar calc-dispatch-help nil)
(defun calc-do-dispatch (&optional _arg)
  "Start the Calculator."
  (let ((key (calc-read-key-sequence
	      (if calc-dispatch-help
		  (substitute-command-keys
                   (concat
                    "Calc options: \\`c'alc, \\`k'eypad, \\`q'uick, \\`e'mbed; "
                    "e\\`x'it; \\`i'nfo, \\`t'utorial; \\`g'rab; \\`?'=more"))
		(format (substitute-command-keys
                         "%s  (Type \\`?' for a list of Calc options)")
			(key-description (this-command-keys))))
	      calc-dispatch-map)))
    (setq key (lookup-key calc-dispatch-map key))
    (message "")
    (if key
	(progn
	  (or (commandp key) (require 'calc-ext))
	  (call-interactively key))
      (beep))))

(defun calc-read-key-sequence (prompt map)
  "Read keys, with prompt PROMPT and keymap MAP."
  (let ((glob (current-global-map))
	(loc (current-local-map)))
    (or (input-pending-p) (message "%s" prompt))
    (let ((key (read-event))
	  (input-method-function nil))
      (calc-unread-command key)
      (unwind-protect
	  (progn
	    (use-global-map map)
	    (use-local-map nil)
	    (read-key-sequence nil))
	(use-global-map glob)
	(use-local-map loc)))))

(defvar calc-alg-map) ; Defined in calc-ext.el


(defvar calc-embedded-modes) ; Defined in calc-embed.el
(defvar calc-override-minor-modes) ; Defined in calc-embed.el
(defun calc-kill-stack-buffer ()
  "Check to see if user wants to kill the Calc stack buffer.
This will look for buffers using the Calc buffer for embedded mode,
and inform the user if there are any.
If the user wants to kill the Calc buffer, this will remove
embedded information from the appropriate buffers and tidy up
the trail buffer."
  (let ((cb (current-buffer))
        (info-list nil)
;        (plural nil)
        (cea calc-embedded-active))
    ;; Get a list of all buffers using this buffer for
    ;; embedded Calc.
    (while cea
      (when (and (eq cb (aref (nth 1 (car cea)) 1))
                 (buffer-name (car (car cea))))
        (setq info-list (cons (car cea) info-list)))
      (setq cea (cdr cea)))
    ;; Eventually, prompt user with a list of buffers using embedded mode.
    (when (and
           info-list
           (yes-or-no-p
            (concat "This Calc stack is being used for embedded mode. Kill anyway?")))
      (while info-list
        (with-current-buffer (car (car info-list))
          (when calc-embedded-info
            (setq calc-embedded-info nil
                  mode-line-buffer-identification (car calc-embedded-modes)
                  truncate-lines (nth 2 calc-embedded-modes)
                  buffer-read-only nil)
            (use-local-map (nth 1 calc-embedded-modes))
            (setq minor-mode-overriding-map-alist
                  (remq calc-override-minor-modes minor-mode-overriding-map-alist))
            (let ((str mode-line-buffer-identification))
              (setq mode-line-buffer-identification str))
            (set-buffer-modified-p (buffer-modified-p))))
        (setq calc-embedded-active
              (delete (car info-list) calc-embedded-active))
        (setq info-list (cdr info-list))))
    (if (not info-list)
        (progn
          (setq calc-buffer-list (delete cb calc-buffer-list))
          (if (buffer-live-p calc-trail-buffer)
              (with-current-buffer calc-trail-buffer
                (if (eq cb calc-main-buffer)
                    ;; If there are other Calc stacks, make another one
                    ;; the calc-main-buffer ...
                    (if calc-buffer-list
                        (setq calc-main-buffer (car calc-buffer-list))
                      ;; ... otherwise kill the trail and its windows.
                      (let ((wl (get-buffer-window-list calc-trail-buffer)))
                        (while wl
                          (delete-window (car wl))
                          (setq wl (cdr wl))))
                      (kill-buffer calc-trail-buffer)))))
          (setq calc-trail-buffer nil)
          t))))

(defvar touch-screen-display-keyboard)

(defun calc-mode ()
  "Calculator major mode.

This is a Reverse Polish notation (RPN) calculator featuring
arbitrary-precision integer, rational, floating-point, complex,
matrix, and symbolic arithmetic.

RPN calculation:  2 RET 3 +    produces 5.
Algebraic style:  \\=' 2+3 RET    produces 5.

Basic operators are +, -, *, /, ^, & (reciprocal), % (modulo), n (change-sign).

Press \\`?' repeatedly for more complete help.  Press \\`h i' to read the
Calc manual, \\`h s' to read the summary, or \\`h t' for the tutorial.

Notations:  3.14e6     3.14 * 10^6
            _23        negative number -23 (or type `23 n')
            17:3       the fraction 17/3
            5:2:3      the fraction 5 and 2/3
            16#12C     the integer 12C base 16 = 300 base 10
            8#177:100  the fraction 177:100 base 8 = 127:64 base 10
            (2, 4)     complex number 2 + 4i
            (2; 4)     polar complex number (r; theta)
            [1, 2, 3]  vector  ([[1, 2], [3, 4]] is a matrix)
            [1 .. 4)   semi-open interval, 1 <= x < 4
            2 +/- 3    (p key) number with mean 2, standard deviation 3
            2 mod 3    (M key) number 2 computed modulo 3
	    <1 jan 91> Date form (enter using \\=' key)


\\{calc-mode-map}"
  (interactive)
  (mapc (lambda (v)
          ;; FIXME: Why (set-default v (symbol-value v)) ?!?!?
          (set-default v (symbol-value v)))
        calc-local-var-list)
  (kill-all-local-variables)
  (use-local-map (if (eq calc-algebraic-mode 'total)
		     (progn (require 'calc-ext) calc-alg-map) calc-mode-map))
  (mapc #'make-local-variable calc-local-var-list)
  (make-local-variable 'overlay-arrow-position)
  (make-local-variable 'overlay-arrow-string)
  (add-hook 'change-major-mode-hook #'font-lock-defontify nil t)
  (add-hook 'kill-buffer-query-functions
            #'calc-kill-stack-buffer
            t t)
  (setq truncate-lines t)
  (setq buffer-read-only t)
  (setq major-mode 'calc-mode)
  (setq mode-name "Calculator")
  (setq calc-stack-top (length (or (memq (assq 'top-of-stack calc-stack)
					 calc-stack)
				   (setq calc-stack (list (list 'top-of-stack
								1 nil))))))
  (setq calc-stack-top (- (length calc-stack) calc-stack-top -1))
  (or calc-loaded-settings-file
      (null calc-settings-file)
      (equal calc-settings-file user-init-file)
      (progn
	(setq calc-loaded-settings-file t)
	(let ((warning-inhibit-types '((files missing-lexbind-cookie))))
          (load (file-name-sans-extension calc-settings-file) t))))   ; t = missing-ok
  (let ((p command-line-args))
    (while p
      (and (equal (car p) "-f")
	   (string-match "calc" (nth 1 p))
	   (string-match "full" (nth 1 p))
	   (setq calc-standalone-flag t))
      (setq p (cdr p))))
  (require 'calc-menu)
  (run-mode-hooks 'calc-mode-hook)
  (calc-refresh t)
  (calc-set-mode-line)
  (calc-check-defines)
  (if calc-buffer-list (setq calc-stack (copy-sequence calc-stack)))
  (add-to-list 'calc-buffer-list (current-buffer) t)
  ;; While Calc buffers are read only, the on screen keyboard should
  ;; be displayed in order to accept user input.
  (setq-local touch-screen-display-keyboard t))

(defvar calc-check-defines 'calc-check-defines)  ; Suitable for run-hooks.
(defun calc-check-defines ()
  (if (symbol-plist 'calc-define)
      (let ((plist (copy-sequence (symbol-plist 'calc-define))))
	(while (and plist (null (nth 1 plist)))
	  (setq plist (cdr (cdr plist))))
	(if plist
	    (save-excursion
	      (require 'calc-ext)
	      (require 'calc-macs)
	      (set-buffer "*Calculator*")
	      (while plist
		(put 'calc-define (car plist) nil)
		(eval (nth 1 plist) t)
		(setq plist (cdr (cdr plist))))
	      ;; See if this has added any more calc-define properties.
	      (calc-check-defines))
	  (setplist 'calc-define nil)))))

(defvar-keymap calc-trail-mode-map
  :parent calc-mode-map)

(defun calc--header-line (long short width &optional fudge)
  "Return a Calc header line appropriate for the buffer WIDTH.

LONG is a desired text for a wide window, SHORT is a desired
abbreviated text, and width is the buffer width, which will be
some fraction of the \"parent\" window width (At the time of
writing, 2/3 for calc, 1/3 for trail).  The optional FUDGE is a
trial-and-error adjustment number for the edge-cases at the
border of the two cases."
  ;; TODO: This could be called as part of a 'window-resize' hook.
  (setq header-line-format
        (let* ((len-long (length long))
               (len-short (length short))
               (fudge (or fudge 0))
               ;; fudge for trail is: -3 (added to len-long)
               ;; (width  ) for trail
               (factor (if (> width (+ len-long fudge)) len-long len-short))
               (size   (max (/ (- width factor) 2) 0))
               (fill (make-string size ?-))
               (pre  (replace-regexp-in-string ".$" " " fill))
               (post (replace-regexp-in-string "^." " " fill)))
          (concat pre (if (= factor len-long) long short) post))))

(define-derived-mode calc-trail-mode fundamental-mode "Calc Trail"
  "Calc Trail mode.
This mode is used by the *Calc Trail* buffer, which records all results
obtained by the GNU Emacs Calculator.

Calculator commands beginning with the t key are used to manipulate
the Trail.

This buffer uses the same key map as the *Calculator* buffer; calculator
commands given here will actually operate on the *Calculator* stack."
  (setq truncate-lines t)
  (setq buffer-read-only t)
  (make-local-variable 'overlay-arrow-position)
  (make-local-variable 'overlay-arrow-string)
  (when calc-show-banner
    (calc--header-line "Emacs Calculator Trail" "Calc Trail"
                       (/ (window-width) 3) -3)))

(defun calc-create-buffer ()
  "Create and initialize a buffer for the Calculator."
  (set-buffer (get-buffer-create "*Calculator*"))
  (or (derived-mode-p 'calc-mode)
      (calc-mode))
  (setq max-lisp-eval-depth (max max-lisp-eval-depth 1000))
  (when calc-always-load-extensions
    (require 'calc-ext))
  (when calc-language
    (require 'calc-ext)
    (calc-set-language calc-language calc-language-option t)))

(defcustom calc-make-windows-dedicated nil
  "If non-nil, windows displaying Calc buffers will be marked dedicated.
See `window-dedicated-p' for what that means."
  :version "28.1"
  :type 'boolean)

;;;###autoload
(defun calc (&optional arg full-display interactive)
  "The Emacs Calculator.  Full documentation is listed under `calc-mode'."
  (interactive "P\ni\np")
  (if arg
      (unless (eq arg 0)
	(require 'calc-ext)
	(if (= (prefix-numeric-value arg) -1)
	    (calc-grab-region (region-beginning) (region-end) nil)
	  (when (= (prefix-numeric-value arg) -2)
	    (calc-keypad))))
    ;; If the selected window changes here, Emacs may think that the
    ;; selected window is read only, and no on screen keyboard should
    ;; be displayed.  Make sure that any active on screen keyboard is
    ;; not hidden by accident.
    (let ((touch-screen-display-keyboard t))
      (when (get-buffer-window "*Calc Keypad*")
        (calc-keypad)
        (set-buffer (window-buffer)))
      (if (derived-mode-p 'calc-mode)
	  (calc-quit)
        (calc-create-buffer)
        (setq calc-was-keypad-mode nil)
        (if (or (eq full-display t)
                (and (null full-display) calc-full-mode))
            (switch-to-buffer (current-buffer) t)
          (if (get-buffer-window (current-buffer))
              (select-window (get-buffer-window (current-buffer)))
            (if calc-window-hook
                (run-hooks 'calc-window-hook)
              (let ((w (get-largest-window)))
                (if (and pop-up-windows
                         (> (window-height w)
                            (+ window-min-height calc-window-height 2)))
                    (progn
                      (setq w (split-window w
                                            (- (window-height w)
                                               calc-window-height 2)
                                            nil))
                      (set-window-buffer w (current-buffer))
                      (select-window w))
                  (pop-to-buffer (current-buffer)))))))
        (with-current-buffer (calc-trail-buffer)
          (and calc-display-trail
               (calc-trail-display 1 t)))
        (message (substitute-command-keys
                  (concat "Welcome to the GNU Emacs Calculator!  \\<calc-mode-map>"
                          "Press \\[calc-help] or \\[calc-help-prefix] for help, \\[calc-quit] to quit")))
        (run-hooks 'calc-start-hook)
        (and (windowp full-display)
             (window-point full-display)
             (select-window full-display))
        (and calc-make-windows-dedicated
             (set-window-dedicated-p nil t))
        (calc-check-defines)
        (when (and calc-said-hello interactive)
          (sit-for 2)
          (message ""))
        (setq calc-said-hello t)))))

;;;###autoload
(defun full-calc (&optional interactive)
  "Invoke the Calculator and give it a full-sized window."
  (interactive "p")
  (calc nil t interactive))

(defun calc-same-interface (arg)
  "Invoke the Calculator using the most recent interface (`calc' or `calc-keypad')."
  (interactive "P")
  (if (and (equal (buffer-name) "*Gnuplot Trail*")
	   (> (recursion-depth) 0))
      (exit-recursive-edit)
    (if (derived-mode-p 'calc-edit-mode)
	(calc-edit-finish arg)
      (if calc-was-keypad-mode
          (calc-keypad)
        (calc arg calc-full-mode t)))))

(defun calc-quit (&optional non-fatal interactive)
  "Quit the Calculator in an appropriate manner."
  (interactive "i\np")
  (and calc-standalone-flag (not non-fatal)
       (save-buffers-kill-emacs nil))
  (if (and (equal (buffer-name) "*Gnuplot Trail*")
	   (> (recursion-depth) 0))
      (exit-recursive-edit))
  (if (derived-mode-p 'calc-edit-mode)
      (calc-edit-cancel)
    (if (and interactive
             calc-embedded-info
             (eq (current-buffer) (aref calc-embedded-info 0)))
        (calc-embedded nil)
      (unless (derived-mode-p 'calc-mode)
        (calc-create-buffer))
      (run-hooks 'calc-end-hook)
      (if (integerp calc-undo-length)
          (cond
           ((= calc-undo-length 0)
            (setq calc-undo-list nil calc-redo-list nil))
           ((> calc-undo-length 0)
            (let ((tail (nthcdr (1- calc-undo-length) calc-undo-list)))
              (if tail (setcdr tail nil)))
            (setq calc-redo-list nil))))
      (mapc (lambda (v) (set-default v (symbol-value v)))
	    calc-local-var-list)
      (let ((buf (current-buffer))
            (win (get-buffer-window (current-buffer)))
            (kbuf (get-buffer "*Calc Keypad*")))
        (delete-windows-on (calc-trail-buffer))
        ;; The next few lines will set `calc-window-height' so that the
        ;; next time Calc is called, the window will be the same size
        ;; as the current window.
        (if (and win
		 (not (window-full-height-p win))
                 (window-full-width-p win) ; avoid calc-keypad
                 (not (get-buffer-window "*Calc Keypad*")))
            (setq calc-window-height (- (window-height win) 2)))
        (progn
          (delete-windows-on buf)
          (and kbuf (delete-windows-on kbuf)))
        (bury-buffer buf)
        (bury-buffer calc-trail-buffer)
        (and kbuf (bury-buffer kbuf))))))

;;;###autoload
(defun quick-calc (&optional insert)
  "Do a quick calculation in the minibuffer without invoking full Calculator.
With prefix argument INSERT, insert the result in the current
buffer.  Otherwise, the result is copied into the kill ring."
  (interactive "P")
  (calc-do-quick-calc insert))

;;;###autoload
(defun calc-eval (str &optional separator &rest args)
  "Do a quick calculation and return the result as a string.
Return value will either be the formatted result in string form,
or a list containing a character position and an error message in string form."
  (calc-do-calc-eval str separator args))

;;;###autoload
(defun calc-keypad (&optional interactive)
  "Invoke the Calculator in \"visual keypad\" mode.
This is most useful in the X window system.
In this mode, click on the Calc \"buttons\" using the left mouse button.
Or, position the cursor manually and do \\[calc-keypad-press]."
  (interactive "p")
  (require 'calc-ext)
  (calc-do-keypad calc-full-mode interactive))

;;;###autoload
(defun full-calc-keypad (&optional interactive)
  "Invoke the Calculator in full-screen \"visual keypad\" mode.
See calc-keypad for details."
  (interactive "p")
  (require 'calc-ext)
  (calc-do-keypad t interactive))


(defvar calc-aborted-prefix nil)
(defvar calc-start-time nil)
(defvar calc-command-flags nil)
(defvar calc-final-point-line)
(defvar calc-final-point-column)
;;; Note that modifications to this function may break calc-pass-errors.
(defun calc-do (do-body &optional do-slow)
  (calc-check-defines)
  (let* ((calc-command-flags nil)
	 (calc-start-time (and calc-timing (not calc-start-time)
			       (require 'calc-ext)
			       (current-time-string)))
	 (gc-cons-threshold (max gc-cons-threshold
				 (if calc-timing 2000000 100000)))
	 calc-final-point-line calc-final-point-column)
    (setq calc-aborted-prefix "")
    (unwind-protect
	(condition-case err
	    (save-excursion
	      (if calc-embedded-info
		  (calc-embedded-select-buffer)
		(calc-select-buffer))
	      (and (eq calc-algebraic-mode 'total)
		   (require 'calc-ext)
		   (use-local-map calc-alg-map))
	      (when (and do-slow calc-display-working-message)
		(message "Working...")
		(calc-set-command-flag 'clear-message))
	      (funcall do-body)
	      (setq calc-aborted-prefix nil)
	      (when (memq 'renum-stack calc-command-flags)
		(calc-renumber-stack))
	      (when (memq 'clear-message calc-command-flags)
		(message "")))
	  (error
	   (if (and (eq (car err) 'error)
		    (stringp (nth 1 err))
		    (string-search "max-lisp-eval-depth" (nth 1 err)))
               (error (substitute-command-keys
                       "Computation got stuck or ran too long.  Type \\`M' to increase the limit"))
	     (setq calc-aborted-prefix nil)
	     (signal (car err) (cdr err)))))
      (when calc-aborted-prefix
	(calc-record "<Aborted>" calc-aborted-prefix))
      (and calc-start-time
	   (let* ((calc-internal-prec 12)
		  (calc-date-format nil)
		  (end-time (current-time-string))
		  (time (if (equal calc-start-time end-time)
			    0
			  (math-sub
			   (calcFunc-unixtime (math-parse-date end-time) 0)
			   (calcFunc-unixtime (math-parse-date calc-start-time)
					      0)))))
	     (if (math-lessp 1 time)
		 (calc-record time "(t)"))))
      (or (memq 'no-align calc-command-flags)
	  (derived-mode-p 'calc-trail-mode)
	  (calc-align-stack-window))
      (and (memq 'position-point calc-command-flags)
	   (if (derived-mode-p 'calc-mode)
	       (progn
		 (goto-char (point-min))
		 (forward-line (1- calc-final-point-line))
		 (move-to-column calc-final-point-column))
	     (save-current-buffer
	       (calc-select-buffer)
	       (goto-char (point-min))
	       (forward-line (1- calc-final-point-line))
	       (move-to-column calc-final-point-column))))
      (unless (memq 'keep-flags calc-command-flags)
	(save-excursion
	  (calc-select-buffer)
	  (setq calc-inverse-flag nil
		calc-hyperbolic-flag nil
                calc-option-flag nil
		calc-keep-args-flag nil)))
      (when (memq 'do-edit calc-command-flags)
	(switch-to-buffer (get-buffer-create "*Calc Edit*")))
      (calc-set-mode-line)
      (when calc-embedded-info
	(calc-embedded-finish-command))))
  (identity nil))  ; allow a GC after timing is done


(defun calc-set-command-flag (f)
  (unless (memq f calc-command-flags)
    (setq calc-command-flags (cons f calc-command-flags))))

(defun calc-select-buffer ()
  (or (derived-mode-p 'calc-mode)
      (if calc-main-buffer
	  (set-buffer calc-main-buffer)
	(let ((buf (get-buffer "*Calculator*")))
	  (if buf
	      (set-buffer buf)
	    (error "Calculator buffer not available"))))))

(defun calc-cursor-stack-index (&optional index)
  (goto-char (point-max))
  (forward-line (- (calc-substack-height (or index 1)))))

(defun calc-stack-size ()
  (- (length calc-stack) calc-stack-top))

(defun calc-substack-height (n)
  (let ((sum 0)
	(stack calc-stack))
    (setq n (+ n calc-stack-top))
    (while (and (> n 0) stack)
      (setq sum (+ sum (nth 1 (car stack)))
	    n (1- n)
	    stack (cdr stack)))
    sum))

(defun calc-set-mode-line ()
  (save-excursion
    (calc-select-buffer)
    (let* ((fmt (car calc-float-format))
	   (figs (nth 1 calc-float-format))
	   (new-mode-string
	    (format "Calc%s%s: %d %s %s"
		    (if (and calc-embedded-info
                             (eq (aref calc-embedded-info 1) (current-buffer)))
                        "Embed" "")
		    (if (and (> (length (buffer-name)) 12)
			     (equal (substring (buffer-name) 0 12)
				    "*Calculator*"))
			(substring (buffer-name) 12)
		      "")
		    calc-internal-prec
		    (capitalize (symbol-name calc-angle-mode))
		    (concat

		     ;; Input-related modes
		     (if (eq calc-algebraic-mode 'total) "Alg* "
		       (if calc-algebraic-mode "Alg "
			 (if calc-incomplete-algebraic-mode "Alg[( " "")))

		     ;; Computational modes
		     (if calc-symbolic-mode "Symb " "")
		     (cond ((eq calc-matrix-mode 'matrix) "Matrix ")
			   ((integerp calc-matrix-mode)
			    (format "Matrix%d " calc-matrix-mode))
			   ((eq calc-matrix-mode 'sqmatrix) "SqMatrix ")
			   ((eq calc-matrix-mode 'scalar) "Scalar ")
			   (t ""))
		     (if (eq calc-complex-mode 'polar) "Polar " "")
		     (if calc-prefer-frac "Frac " "")
		     (cond ((null calc-infinite-mode) "")
			   ((eq calc-infinite-mode 1) "+Inf ")
			   (t "Inf "))
		     (cond ((eq calc-simplify-mode 'none) "NoSimp ")
			   ((eq calc-simplify-mode 'num) "NumSimp ")
			   ((eq calc-simplify-mode 'binary)
			    (format "BinSimp%d " calc-word-size))
			   ((eq calc-simplify-mode 'alg) "")
			   ((eq calc-simplify-mode 'ext) "ExtSimp ")
			   ((eq calc-simplify-mode 'units) "UnitSimp ")
			   (t "BasicSimp "))

		     ;; Display modes
		     (cond ((= calc-number-radix 10) "")
			   ((= calc-number-radix 2) "Bin ")
			   ((= calc-number-radix 8) "Oct ")
			   ((= calc-number-radix 16) "Hex ")
			   (t (format "Radix%d " calc-number-radix)))
                     (if calc-twos-complement-mode "TwosComp " "")
		     (if calc-leading-zeros "Zero " "")
		     (cond ((null calc-language) "")
                           ((get calc-language 'math-lang-name)
                            (concat (get calc-language 'math-lang-name) " "))
			   (t (concat
			       (capitalize (symbol-name calc-language))
			       " ")))
		     (cond ((eq fmt 'float)
			    (if (zerop figs) "" (format "Norm%d " figs)))
			   ((eq fmt 'fix) (format "Fix%d " figs))
			   ((eq fmt 'sci)
			    (if (zerop figs) "Sci " (format "Sci%d " figs)))
			   ((eq fmt 'eng)
			    (if (zerop figs) "Eng " (format "Eng%d " figs))))
		     (cond ((not calc-display-just)
			    (if calc-display-origin
				(format "Left%d " calc-display-origin) ""))
			   ((eq calc-display-just 'right)
			    (if calc-display-origin
				(format "Right%d " calc-display-origin)
			      "Right "))
			   (t
			    (if calc-display-origin
				(format "Center%d " calc-display-origin)
			      "Center ")))
		     (cond ((integerp calc-line-breaking)
			    (format "Wid%d " calc-line-breaking))
			   (calc-line-breaking "")
			   (t "Wide "))

		     ;; Miscellaneous other modes/indicators
		     (if calc-assoc-selections "" "Break ")
		     (cond ((eq calc-mode-save-mode 'save) "Save ")
			   ((not calc-embedded-info) "")
			   ((eq calc-mode-save-mode 'local) "Local ")
			   ((eq calc-mode-save-mode 'edit) "LocEdit ")
			   ((eq calc-mode-save-mode 'perm) "LocPerm ")
			   ((eq calc-mode-save-mode 'global) "Global ")
			   (t ""))
		     (if calc-auto-recompute "" "Manual ")
		     (if (and (fboundp 'calc-gnuplot-alive)
			      (calc-gnuplot-alive)) "Graph " "")
		     (if (and calc-embedded-info
			      (> (calc-stack-size) 0)
			      (calc-top 1 'sel)) "Sel " "")
		     (if calc-display-dirty "Dirty " "")
                     (if calc-option-flag "Opt " "")
		     (if calc-inverse-flag "Inv " "")
		     (if calc-hyperbolic-flag "Hyp " "")
		     (if calc-keep-args-flag "Keep " "")
		     (if (/= calc-stack-top 1) "Narrow " "")
		     (apply #'concat calc-other-modes)))))
      (if (equal new-mode-string mode-line-buffer-identification)
	  nil
	(setq mode-line-buffer-identification new-mode-string)
	(set-buffer-modified-p (buffer-modified-p))
	(and calc-embedded-info (calc-embedded-mode-line-change))))))

(defun calc-align-stack-window ()
  (if (derived-mode-p 'calc-mode)
      (progn
	(let ((win (get-buffer-window (current-buffer))))
	  (if win
	      (progn
		(calc-cursor-stack-index 0)
		(vertical-motion (- 3 (window-height win 'floor)))
		(set-window-start win (point)))))
	(calc-cursor-stack-index 0)
	(if (looking-at " *\\.$")
	    (goto-char (1- (match-end 0)))))
    (save-excursion
      (calc-select-buffer)
      (calc-align-stack-window))))

(defun calc-check-stack (n)
  (if (> n (calc-stack-size))
      (error "Too few elements on stack"))
  (if (< n 0)
      (error "Invalid argument")))

(defun calc-push-list (vals &optional m sels)
  (while vals
    (if calc-executing-macro
	(calc-push-list-in-macro vals m sels)
      (save-excursion
	(calc-select-buffer)
	(let* ((val (car vals))
	       (entry (list val 1 (car sels)))
	       (mm (+ (or m 1) calc-stack-top)))
	  (calc-cursor-stack-index (1- (or m 1)))
	  (if (> mm 1)
	      (setcdr (nthcdr (- mm 2) calc-stack)
		      (cons entry (nthcdr (1- mm) calc-stack)))
	    (setq calc-stack (cons entry calc-stack)))
	  (let ((buffer-read-only nil))
	    (insert (math-format-stack-value entry) "\n"))
	  (calc-record-undo (list 'push mm))
	  (calc-set-command-flag 'renum-stack))))
    (setq vals (cdr vals)
	  sels (cdr sels))))

(defun calc-pop-push-list (n vals &optional m sels)
  (if (and calc-any-selections (null sels))
      (calc-replace-selections n vals m)
    (calc-pop-stack n m sels)
    (calc-push-list vals m sels)))

(defun calc-pop-push-record-list (n prefix vals &optional m sels)
  (or (and (consp vals)
	   (or (integerp (car vals))
	       (consp (car vals))))
      (and vals (setq vals (list vals)
		      sels (and sels (list sels)))))
  (calc-check-stack (+ n (or m 1) -1))
  (if prefix
      (if (cdr vals)
	  (calc-record-list vals prefix)
	(calc-record (car vals) prefix)))
  (calc-pop-push-list n vals m sels))

(defun calc-enter-result (n prefix vals &optional m)
  (setq calc-aborted-prefix prefix)
  (if (and (consp vals)
	   (or (integerp (car vals))
	       (consp (car vals))))
      (setq vals (mapcar #'calc-normalize vals))
    (setq vals (calc-normalize vals)))
  (or (and (consp vals)
	   (or (integerp (car vals))
	       (consp (car vals))))
      (setq vals (list vals)))
  (if (equal vals '((nil)))
      (setq vals nil))
  (calc-pop-push-record-list n prefix vals m)
  (calc-handle-whys))

(defun calc-normalize (val)
  (if (memq calc-simplify-mode '(nil none num))
      (math-normalize val)
    (require 'calc-ext)
    (calc-normalize-fancy val)))

(defun calc-handle-whys ()
  (if calc-next-why
      (calc-do-handle-whys)))


(defun calc-pop-stack (&optional n m sel-ok)  ; pop N objs at level M of stack.
  (or n (setq n 1))
  (or m (setq m 1))
  (or calc-keep-args-flag
      (let ((mm (+ m calc-stack-top)))
	(if (and calc-any-selections (not sel-ok)
		 (calc-top-selected n m))
	    (calc-sel-error))
	(if calc-executing-macro
	    (calc-pop-stack-in-macro n mm)
	  (calc-record-undo (list 'pop mm (calc-top-list n m 'full)))
	  (save-excursion
	    (calc-select-buffer)
	    (let ((buffer-read-only nil))
	      (if (> mm 1)
		  (progn
		    (calc-cursor-stack-index (1- m))
		    (let ((bot (point)))
		      (calc-cursor-stack-index (+ n m -1))
		      (delete-region (point) bot))
		    (setcdr (nthcdr (- mm 2) calc-stack)
			    (nthcdr (+ n mm -1) calc-stack)))
		(calc-cursor-stack-index n)
		(setq calc-stack (nthcdr n calc-stack))
		(delete-region (point) (point-max))))
	    (calc-set-command-flag 'renum-stack))))))

(defun calc-get-stack-element (x &optional sel-mode)
  (cond ((eq sel-mode 'entry)
	 x)
	((eq sel-mode 'sel)
	 (nth 2 x))
	((or (null (nth 2 x))
	     (eq sel-mode 'full)
	     (not calc-use-selections))
	 (car x))
	(sel-mode
	 (calc-sel-error))
	(t (nth 2 x))))

;; Get the Nth element of the stack (N=1 is the top element).
(defun calc-top (&optional n sel-mode)
  (or n (setq n 1))
  (calc-check-stack n)
  (calc-get-stack-element (nth (+ n calc-stack-top -1) calc-stack) sel-mode))

(defun calc-top-n (&optional n sel-mode)    ; In case precision has changed.
  (math-check-complete (calc-normalize (calc-top n sel-mode))))

(defun calc-top-list (&optional n m sel-mode)
  (or n (setq n 1))
  (or m (setq m 1))
  (calc-check-stack (+ n m -1))
  (nreverse (mapcar (lambda (x) (calc-get-stack-element x sel-mode))
                    (take n (nthcdr (+ m calc-stack-top -1) calc-stack)))))

(defun calc-top-list-n (&optional n m sel-mode)
  (mapcar #'math-check-complete
	  (mapcar #'calc-normalize (calc-top-list n m sel-mode))))


(defun calc-renumber-stack ()
  (if calc-line-numbering
      (save-excursion
	(calc-cursor-stack-index 0)
	(let ((lnum 1)
	      (buffer-read-only nil)
	      (stack (nthcdr calc-stack-top calc-stack)))
	  (if (re-search-forward "^[0-9]+[:*]" nil t)
	      (progn
		(beginning-of-line)
		(while (re-search-forward "^[0-9]+[:*]" nil t)
		  (let ((buffer-read-only nil))
		    (beginning-of-line)
		    (delete-char 4)
		    (insert "    ")))
		(calc-cursor-stack-index 0)))
	  (while (re-search-backward "^[0-9]+[:*]" nil t)
	    (delete-char 4)
	    (if (> lnum 999)
		(insert (format "%03d%s" (% lnum 1000)
				(if (and (nth 2 (car stack))
					 calc-use-selections) "*" ":")))
	      (let ((prefix (int-to-string lnum)))
		(insert prefix (if (and (nth 2 (car stack))
					calc-use-selections) "*" ":")
			(make-string (- 3 (length prefix)) 32))))
	    (beginning-of-line)
	    (setq lnum (1+ lnum)
		  stack (cdr stack))))))
  (and calc-embedded-info (calc-embedded-stack-change)))

(defvar calc-any-evaltos nil)
(defun calc-refresh (&optional align)
  (interactive)
  (and (derived-mode-p 'calc-mode)
       (not calc-executing-macro)
       (let* ((inhibit-read-only t)
	      (save-point (point))
	      (save-mark (ignore-errors (mark)))
	      (save-aligned (looking-at "\\.$"))
	      (thing calc-stack)
	      (calc-any-evaltos nil))
	 (setq calc-any-selections nil)
	 (erase-buffer)
         (when calc-show-banner
           (calc--header-line  "Emacs Calculator Mode" "Emacs Calc"
                       (* 2 (/ (window-width) 3)) -3))
	 (while thing
	   (goto-char (point-min))
	   (insert (math-format-stack-value (car thing)) "\n")
	   (setq thing (cdr thing)))
	 (calc-renumber-stack)
	 (if calc-display-dirty
	     (calc-wrapper (setq calc-display-dirty nil)))
	 (and calc-any-evaltos calc-auto-recompute
	      (calc-wrapper (calc-refresh-evaltos)))
	 (if (or align save-aligned)
	     (calc-align-stack-window)
	   (goto-char save-point))
	 (if save-mark (set-mark save-mark))))
  (and calc-embedded-info (not (derived-mode-p 'calc-mode))
       (with-current-buffer (aref calc-embedded-info 1)
	 (calc-refresh align)))
  (setq calc-refresh-count (1+ calc-refresh-count)))

;; Dates that are built-in options for `calc-gregorian-switch' should be
;; (YEAR MONTH DAY math-date-from-gregorian-dt(YEAR MONTH DAY)) for speed.
(defcustom calc-gregorian-switch nil
  "The first day the Gregorian calendar is used by Calc's date forms.
This is nil (the default) if the Gregorian calendar is the only one used.
Otherwise, it should be a list `(YEAR MONTH DAY)' when Calc begins to use
the Gregorian calendar; Calc will use the Julian calendar for earlier dates.
The dates in which different regions of the world began to use the
Gregorian calendar vary quite a bit, even within a single country.
If you want Calc's date forms to switch between the Julian and
Gregorian calendar, you can specify the date or choose from several
common choices.  Some of these choices should be taken with a grain
of salt; for example different parts of France changed calendars at
different times, and Sweden's change to the Gregorian calendar was
complicated.  Also, the boundaries of the countries were different at
the times of the calendar changes than they are now.
The Vatican decided that the Gregorian calendar should take effect
on 15 October 1582 (Gregorian), and many Catholic countries made
the change then.  Great Britain and its colonies had the Gregorian
calendar take effect on 14 September 1752 (Gregorian); this includes
the United States."
  :version "24.4"
  :type '(choice (const :tag "Always use the Gregorian calendar" nil)
                 (const :tag "1582-10-15 - Italy, Poland, Portugal, Spain" (1582 10 15 577736))
                 (const :tag "1582-12-20 - France" (1582 12 20 577802))
                 (const :tag "1582-12-25 - Luxemburg" (1582 12 25 577807))
                 (const :tag "1584-01-17 - Bohemia and Moravia" (1584 1 17 578195))
                 (const :tag "1587-11-01 - Hungary" (1587 11 1 579579))
                 (const :tag "1700-03-01 - Denmark" (1700 3 1 620607))
                 (const :tag "1701-01-12 - Protestant Switzerland" (1701 1 12 620924))
                 (const :tag "1752-09-14 - Great Britain and dominions" (1752 9 14 639797))
                 (const :tag "1753-03-01 - Sweden" (1753 3 1 639965))
                 (const :tag "1918-02-14 - Russia" (1918 2 14 700214))
                 (const :tag "1919-04-14 - Romania" (1919 4 14 700638))
                 (list :tag "(YEAR MONTH DAY)"
                       (integer :tag "Year")
                       (integer :tag "Month (integer)")
                       (integer :tag "Day")))
  :set (lambda (symbol value)
         (set-default symbol value)
         (setq math-format-date-cache nil)
         (calc-refresh)))

;;;; The Calc Trail buffer.

(defun calc-check-trail-aligned ()
  (save-excursion
    (let ((win (get-buffer-window (current-buffer))))
      (and win
	   (pos-visible-in-window-p (1- (point-max)) win)))))

(defun calc-trail-buffer ()
  (and (or (null calc-trail-buffer)
	   (null (buffer-name calc-trail-buffer)))
       (save-excursion
	 (setq calc-trail-buffer (get-buffer-create "*Calc Trail*"))
	 (let ((buf (or (and (not (derived-mode-p 'calc-mode))
			     (get-buffer "*Calculator*"))
			(current-buffer))))
	   (set-buffer calc-trail-buffer)
	   (unless (derived-mode-p 'calc-trail-mode)
             (calc-trail-mode)
             (setq-local calc-main-buffer buf)))))
  (or (and calc-trail-pointer
	   (eq (marker-buffer calc-trail-pointer) calc-trail-buffer))
      (with-current-buffer calc-trail-buffer
	(goto-char (point-min))
	(setq calc-trail-pointer (point-marker))))
  calc-trail-buffer)

(defvar calc-can-abbrev-vectors)

(defun calc-record (val &optional prefix)
  (setq calc-aborted-prefix nil)
  (or calc-executing-macro
      (let* ((buf (calc-trail-buffer))
	     (calc-display-raw nil)
	     (calc-can-abbrev-vectors t)
	     (fval (if val
		       (if (stringp val)
			   val
			 (math-showing-full-precision
			  (math-format-flat-expr val 0)))
		     "")))
	(with-current-buffer buf
	  (let ((aligned (calc-check-trail-aligned))
		(buffer-read-only nil))
	    (goto-char (point-max))
	    (cond ((null prefix) (insert "     "))
		  ((and (> (length prefix) 4)
			(string-search " " prefix 4))
		   (insert (substring prefix 0 4) " "))
		  (t (insert (format "%4s " prefix))))
	    (insert fval "\n")
	    (let ((win (get-buffer-window buf)))
	      (if (and aligned win (not (memq 'hold-trail calc-command-flags)))
		  (calc-trail-here))
	      (goto-char (1- (point-max))))))))
  val)


(defun calc-trail-display (flag &optional no-refresh interactive)
  (interactive "P\ni\np")
  (let ((win (get-buffer-window (calc-trail-buffer))))
    (if (setq calc-display-trail
	      (not (if flag (memq flag '(nil 0)) win)))
	(if (null win)
	    (progn
              (if calc-trail-window-hook
                  (run-hooks 'calc-trail-window-hook)
                (let ((w (split-window nil (/ (* (window-width) 2) 3) t)))
                  (set-window-buffer w calc-trail-buffer)
                  (and calc-make-windows-dedicated
                       (set-window-dedicated-p w t))))
              (calc-wrapper
               (setq overlay-arrow-string calc-trail-overlay
                     overlay-arrow-position calc-trail-pointer)
               (or no-refresh
                   (if interactive
                       (calc-do-refresh)
                     (calc-refresh))))))
      (if win
	  (progn
	    (delete-window win)
	    (calc-wrapper
	     (or no-refresh
		 (if interactive
		     (calc-do-refresh)
		   (calc-refresh))))))))
  calc-trail-buffer)

(defun calc-trail-here ()
  (interactive)
  (if (derived-mode-p 'calc-trail-mode)
      (progn
	(beginning-of-line)
	(if (eobp)
            (forward-line -1))
	(if (and (bobp) (eobp))
	    (setq overlay-arrow-position nil)   ; trail is empty
	  (set-marker calc-trail-pointer (point) (current-buffer))
	  (setq calc-trail-overlay (concat (buffer-substring (point)
							     (+ (point) 4))
					   ">")
		overlay-arrow-string calc-trail-overlay
		overlay-arrow-position calc-trail-pointer)
	  (forward-char 4)
	  (let ((win (get-buffer-window (current-buffer))))
	    (if win
		(save-excursion
		  (forward-line (/ (window-height win) 2))
		  (forward-line (- 2 (window-height win)))
		  (set-window-start win (point))
		  (set-window-point win (+ calc-trail-pointer 4))
		  (set-buffer calc-main-buffer)
		  (setq overlay-arrow-string calc-trail-overlay
			overlay-arrow-position calc-trail-pointer))))))
    (error "Not in Calc Trail buffer")))




;;;; The Undo list.

(defun calc-record-undo (rec)
  (or calc-executing-macro
      (if (memq 'undo calc-command-flags)
	  (setq calc-undo-list (cons (cons rec (car calc-undo-list))
				     (cdr calc-undo-list)))
	(setq calc-undo-list (cons (list rec) calc-undo-list)
	      calc-redo-list nil)
	(calc-set-command-flag 'undo))))




;;; Arithmetic commands.

(defun calc-binary-op (name func arg &optional ident unary func2)
  (setq calc-aborted-prefix name)
  (if (null arg)
      (calc-enter-result 2 name (cons (or func2 func)
				      (mapcar #'math-check-complete
					      (calc-top-list 2))))
    (require 'calc-ext)
    (calc-binary-op-fancy name func arg ident unary)))

(defun calc-unary-op (name func arg &optional func2)
  (setq calc-aborted-prefix name)
  (if (null arg)
      (calc-enter-result 1 name (list (or func2 func)
				      (math-check-complete (calc-top 1))))
    (require 'calc-ext)
    (calc-unary-op-fancy name func arg)))


(defun calc-plus (arg)
  (interactive "P")
  (calc-slow-wrapper
   (calc-binary-op "+" 'calcFunc-add arg 0 nil '+)))

(defun calc-minus (arg)
  (interactive "P")
  (calc-slow-wrapper
   (calc-binary-op "-" 'calcFunc-sub arg 0 'neg '-)))

(defun calc-times (arg)
  (interactive "P")
  (calc-slow-wrapper
   (calc-binary-op "*" 'calcFunc-mul arg 1 nil '*)))

(defun calc-divide (arg)
  (interactive "P")
  (calc-slow-wrapper
   (calc-binary-op "/" 'calcFunc-div arg 0 'calcFunc-inv '/)))

(defun calc-left-divide (arg)
  (interactive "P")
  (calc-slow-wrapper
   (calc-binary-op "ldiv" 'calcFunc-ldiv arg 0 nil nil)))

(defun calc-change-sign (arg)
  (interactive "P")
  (calc-wrapper
   (calc-unary-op "chs" 'neg arg)))



;;; Stack management commands.

(defun calc-enter (n)
  (interactive "p")
  (let ((num (if calc-context-sensitive-enter (max 1 (calc-locate-cursor-element (point))))))
    (calc-wrapper
     (cond ((< n 0)
            (calc-push-list (calc-top-list 1 (- n))))
           ((= n 0)
            (calc-push-list (calc-top-list (calc-stack-size))))
           (num
            (calc-push-list (calc-top-list n num)))
           (t
            (calc-push-list (calc-top-list n)))))
    (if (and calc-context-sensitive-enter (> n 0)) (calc-cursor-stack-index (+ num n)))))

(defun calc-pop (n)
  (interactive "P")
  (let ((num (if calc-context-sensitive-enter (max 1 (calc-locate-cursor-element (point))))))
    (calc-wrapper
     (let* ((nn (prefix-numeric-value n))
            (top (and (null n) (calc-top 1))))
       (cond ((and calc-context-sensitive-enter (> num 1))
              (calc-pop-stack nn num))
             ((and (null n)
                   (eq (car-safe top) 'incomplete)
                   (> (length top) (if (eq (nth 1 top) 'intv) 3 2)))
              (calc-pop-push-list 1 (list (butlast top))))
             ((< nn 0)
              (if (and calc-any-selections
                       (calc-top-selected 1 (- nn)))
                  (calc-delete-selection (- nn))
                (calc-pop-stack 1 (- nn) t)))
             ((= nn 0)
              (calc-pop-stack (calc-stack-size) 1 t))
             (t
              (if (and calc-any-selections
                       (= nn 1)
                       (calc-top-selected 1 1))
                  (calc-delete-selection 1)
                (calc-pop-stack nn))))))
    (if calc-context-sensitive-enter (calc-cursor-stack-index (1- num)))))





;;;; Reading a number using the minibuffer.
(defun calc-digit-start-entry ()
  (cond ((eq last-command-event ?e)
         (if (> calc-number-radix 14) (format "%d.^" calc-number-radix) "1e"))
        ((eq last-command-event ?#) (format "%d#" calc-number-radix))
        ((eq last-command-event ?_) "-")
        ((eq last-command-event ?@) "0@ ")
        (t (char-to-string last-command-event))))

(defvar calc-buffer nil)
(defvar calc-prev-char)
(defvar calc-prev-prev-char)
(defvar calc-digit-value)
(defun calcDigit-start ()
  (interactive)
  (calc-wrapper
   (if (or calc-algebraic-mode
	   (and (> calc-number-radix 14) (eq last-command-event ?e)))
       (calc-alg-digit-entry)
     (setq calc-aborted-prefix nil)
     (let* ((calc-digit-value nil)
	    (calc-prev-char last-command-event)
	    (calc-prev-prev-char nil)
	    (calc-buffer (current-buffer))
	    (buf
	     (let ((old-esc (lookup-key global-map "\e")))
	       (unwind-protect
		   (progn
		     (define-key global-map "\e" nil)
		     (read-from-minibuffer
                      "Calc: " (calc-digit-start-entry) calc-digit-map))
		 (define-key global-map "\e" old-esc)))))
       (or calc-digit-value (setq calc-digit-value (math-read-number buf)))
       (if (stringp calc-digit-value)
	   (calc-alg-entry calc-digit-value)
	 (if calc-digit-value
	     (calc-push-list (list (calc-record (calc-normalize
						 calc-digit-value))))))
       (if (eq calc-prev-char 'dots)
	   (progn
	     (require 'calc-ext)
	     (calc-dots)))))))

(defsubst calc-minibuffer-size ()
  (- (point-max) (minibuffer-prompt-end)))

(defun calcDigit-nondigit ()
  (interactive)
  ;; Exercise for the reader:  Figure out why this is a good precaution!
  (or calc-buffer
      (use-local-map minibuffer-local-map))
  (let ((str (minibuffer-contents)))
    (setq calc-digit-value (with-current-buffer calc-buffer
			     (math-read-number str))))
  (if (and (null calc-digit-value) (> (calc-minibuffer-size) 0))
      (progn
	(beep)
	(calc-temp-minibuffer-message " [Bad format]"))
    (or (memq last-command-event '(32 13))
	(progn (setq prefix-arg current-prefix-arg)
	       (calc-unread-command (if (and (eq last-command-event 27)
					     (>= last-input-event 128))
					last-input-event
				      nil))))
    (exit-minibuffer)))


(defun calc-minibuffer-contains (rex)
  (save-excursion
    (goto-char (minibuffer-prompt-end))
    (looking-at rex)))

(defun calcDigit-key ()
  (interactive)
  (if (or (and (memq last-command-event '(?+ ?-))
	       (> (buffer-size) 0)
	       (/= (preceding-char) ?e))
	  (and (memq last-command-event '(?m ?s))
	       (not (calc-minibuffer-contains "[-+]?[0-9]+\\.?0*[@oh].*"))
	       (not (calc-minibuffer-contains "[-+]?\\(1[1-9]\\|[2-9][0-9]\\)#.*"))))
      (calcDigit-nondigit)
    (if (calc-minibuffer-contains "\\([-+]?\\|.* \\)\\'")
	(cond ((memq last-command-event '(?. ?@)) (insert "0"))
	      ((and (memq last-command-event '(?o ?h ?m))
		    (not (calc-minibuffer-contains ".*#.*"))) (insert "0"))
	      ((memq last-command-event '(?: ?e)) (insert "1"))
	      ((eq last-command-event ?#)
	       (insert (int-to-string calc-number-radix)))))
    (if (and (calc-minibuffer-contains "\\([-+]?[0-9]+#\\|[^:]*:\\)\\'")
	     (eq last-command-event ?:))
	(insert "1"))
    (if (and (calc-minibuffer-contains "[-+]?[0-9]+#\\'")
	     (eq last-command-event ?.))
	(insert "0"))
    (if (and (calc-minibuffer-contains "[-+]?0*\\([2-9]\\|1[0-4]\\)#\\'")
	     (eq last-command-event ?e))
	(insert "1"))
    (if (or (and (memq last-command-event '(?h ?o ?m ?s ?p))
		 (calc-minibuffer-contains ".*#.*"))
	    (and (eq last-command-event ?e)
		 (calc-minibuffer-contains "[-+]?\\(1[5-9]\\|[2-9][0-9]\\)#.*"))
	    (and (eq last-command-event ?n)
		 (calc-minibuffer-contains "[-+]?\\(2[4-9]\\|[3-9][0-9]\\)#.*")))
	(setq last-command-event (upcase last-command-event)))
    (cond
     ((memq last-command-event '(?_ ?n))
      (goto-char (minibuffer-prompt-end))
      (if (and (search-forward " +/- " nil t)
	       (not (search-forward "e" nil t)))
	  (beep)
	(and (not (calc-minibuffer-contains "[-+]?\\(1[5-9]\\|[2-9][0-9]\\)#.*"))
	     (search-forward "e" nil t))
	(if (looking-at "\\+")
	    (delete-char 1))
	(if (looking-at "-")
	    (delete-char 1)
	  (insert "-"))))
     ((eq last-command-event ?p)
      (if (or (calc-minibuffer-contains ".*\\+/-.*")
	      (calc-minibuffer-contains ".*mod.*")
	      (calc-minibuffer-contains ".*#.*")
	      (calc-minibuffer-contains ".*[-+e:]\\'"))
	  (beep)
	(if (not (calc-minibuffer-contains ".* \\'"))
	    (insert " "))
	(insert "+/- ")))
     ((and (eq last-command-event ?M)
	   (not (calc-minibuffer-contains
		 "[-+]?\\(2[3-9]\\|[3-9][0-9]\\)#.*")))
      (if (or (calc-minibuffer-contains ".*\\+/-.*")
	      (calc-minibuffer-contains ".*mod *[^ ]+")
	      (calc-minibuffer-contains ".*[-+e:]\\'"))
	  (beep)
	(if (calc-minibuffer-contains ".*mod \\'")
	    (if calc-previous-modulo
		(insert (math-format-flat-expr calc-previous-modulo 0))
	      (beep))
	  (if (not (calc-minibuffer-contains ".* \\'"))
	      (insert " "))
	  (insert "mod "))))
     (t
      (insert (char-to-string last-command-event))
      (if (or (and (calc-minibuffer-contains "[-+]?\\(.*\\+/- *\\|.*mod *\\)?\\([0-9][0-9]?\\)#[#]?[0-9a-zA-Z]*\\(:[0-9a-zA-Z]*\\(:[0-9a-zA-Z]*\\)?\\|.[0-9a-zA-Z]*\\(e[-+]?[0-9]*\\)?\\)?\\'")
		   (let ((radix (string-to-number
				 (buffer-substring
				  (match-beginning 2) (match-end 2)))))
		     (and (>= radix 2)
			  (<= radix 36)
			  (or (memq last-command-event '(?# ?: ?. ?e ?+ ?-))
			      (let ((dig (math-read-radix-digit
					  (upcase last-command-event))))
				(and dig
				     (< dig radix)))))))
	      (calc-minibuffer-contains
	       "[-+]?\\(.*\\+/- *\\|.*mod *\\)?\\([0-9]+\\.?0*[@oh] *\\)?\\([0-9]+\\.?0*['m] *\\)?[0-9]*\\(\\.?[0-9]*\\(e[-+]?[0-3]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?\\)?\\|[0-9]:\\([0-9]+:\\)?[0-9]*\\)?[\"s]?\\'"))
	  (if (and (memq last-command-event '(?@ ?o ?h ?\' ?m))
		   (string-search " " calc-hms-format))
	      (insert " "))
	(if (and (memq last-command '(calcDigit-start calcDigit-key))
		 (eq last-command-event ?.))
	    (progn
	      (require 'calc-ext)
	      (calc-digit-dots))
	  (delete-char -1)
	  (beep)
	  (calc-temp-minibuffer-message " [Bad format]"))))))
  (setq calc-prev-prev-char calc-prev-char
	calc-prev-char last-command-event))

(defun calcDigit-backspace ()
  (interactive)
  (cond ((eq last-command 'calcDigit-start)
	 (delete-minibuffer-contents))
	(t (with-suppressed-warnings ((interactive-only backward-delete-char))
             (backward-delete-char 1))))
  (if (= (calc-minibuffer-size) 0)
      (progn
	(setq last-command-event 13)
	(calcDigit-nondigit))))

;;;; Arithmetic routines.
;;
;; An object as manipulated by one of these routines may take any of the
;; following forms:
;;
;; integer                 An integer.
;;
;; (frac NUM DEN)          A fraction.  NUM and DEN are integers.
;;                         Normalized, DEN > 1.
;;
;; (float NUM EXP)         A floating-point number, NUM * 10^EXP;
;;                         NUM and EXP are integers.
;;			    Normalized, NUM is not a multiple of 10, and
;;			    abs(NUM) < 10^calc-internal-prec.
;;			    Normalized zero is stored as (float 0 0).
;;
;; (cplx REAL IMAG)        A complex number; REAL and IMAG are any of above.
;;			    Normalized, IMAG is nonzero.
;;
;; (polar R THETA)         Polar complex number.  Normalized, R > 0 and THETA
;;                         is neither zero nor 180 degrees (pi radians).
;;
;; (vec A B C ...)         Vector of objects A, B, C, ...  A matrix is a
;;                         vector of vectors.
;;
;; (hms H M S)             Angle in hours-minutes-seconds form.  All three
;;                         components have the same sign; H and M must be
;;                         numerically integers; M and S are expected to
;;                         lie in the range [0,60).
;;
;; (date N)                A date or date/time object.  N is an integer to
;;			    store a date only, or a fraction or float to
;;			    store a date and time.
;;
;; (sdev X SIGMA)          Error form, X +/- SIGMA.  When normalized,
;;                         SIGMA > 0.  X is any complex number and SIGMA
;;			    is real numbers; or these may be symbolic
;;                         expressions where SIGMA is assumed real.
;;
;; (intv MASK LO HI)       Interval form.  MASK is 0=(), 1=(], 2=[), or 3=[].
;;                         LO and HI are any real numbers, or symbolic
;;			    expressions which are assumed real, and LO < HI.
;;			    For [LO..HI], if LO = HI normalization produces LO,
;;			    and if LO > HI normalization produces [LO..LO).
;;			    For other intervals, if LO > HI normalization
;;			    sets HI equal to LO.
;;
;; (mod N M)	    	    Number modulo M.  When normalized, 0 <= N < M.
;;			    N and M are real numbers.
;;
;; (var V S)		    Symbolic variable.  V is a Lisp symbol which
;;			    represents the variable's visible name.  S is
;;			    the symbol which actually stores the variable's
;;			    value:  (var pi var-pi).
;;
;; In general, combining rational numbers in a calculation always produces
;; a rational result, but if either argument is a float, result is a float.

;; In the following comments, [x y z] means result is x, args must be y, z,
;; respectively, where the code letters are:
;;
;;    O  Normalized object (vector or number)
;;    V  Normalized vector
;;    N  Normalized number of any type
;;    N  Normalized complex number
;;    R  Normalized real number (float or rational)
;;    F  Normalized floating-point number
;;    T  Normalized rational number
;;    I  Normalized integer
;;    B  Normalized big integer
;;    S  Normalized small integer
;;    D  Digit (small integer, 0..999)
;;    L  normalized vector element list (without "vec")
;;    P  Predicate (truth value)
;;    X  Any Lisp object
;;    Z  "nil"
;;
;; Lower-case letters signify possibly un-normalized values.
;; "L.D" means a cons of an L and a D.
;; [N N; n n] means result will be normalized if argument is.
;; Also, [Public] marks routines intended to be called from outside.
;; [This notation has been neglected in many recent routines.]

(defvar math-eval-rules-cache)
(defvar math-eval-rules-cache-other)
;;; Reduce an object to canonical (normalized) form.  [O o; Z Z] [Public]

(defvar math-normalize-error nil
  "Non-nil if the last call the `math-normalize' returned an error.")

(defun math-normalize (a)
  (setq math-normalize-error nil)
  (cond
   ((not (consp a)) a)
   ((eq (car a) 'float)
    (math-make-float (math-normalize (nth 1 a))
                     (nth 2 a)))
   ((or (memq (car a)
              '(frac cplx polar hms date mod sdev intv vec var quote
                     special-const calcFunc-if calcFunc-lambda
                     calcFunc-quote calcFunc-condition
                     calcFunc-evalto))
	(integerp (car a))
	(and (consp (car a))
             (not (eq (car (car a)) 'lambda))))
    (require 'calc-ext)
    (math-normalize-fancy a))
   (t
    (or (and calc-simplify-mode
	     (require 'calc-ext)
             (math-normalize-nonstandard a))
	(let ((args (mapcar #'math-normalize (cdr a))))
	  (or (condition-case err
		  (let ((func
                         (assq (car a) '( ( + . math-add )
                                          ( - . math-sub )
                                          ( * . math-mul )
                                          ( / . math-div )
                                          ( % . math-mod )
                                          ( ^ . math-pow )
                                          ( neg . math-neg )
                                          ( | . math-concat ) ))))
		    (or (and var-EvalRules
			     (progn
			       (or (eq var-EvalRules math-eval-rules-cache-tag)
				   (progn
				     (require 'calc-ext)
				     (math-recompile-eval-rules)))
			       (and (or math-eval-rules-cache-other
					(assq (car a)
                                              math-eval-rules-cache))
				    (math-apply-rewrites
				     (cons (car a) args)
				     (cdr math-eval-rules-cache)
				     nil math-eval-rules-cache))))
			(if func
			    (apply (cdr func) args)
			  (and (or (consp (car a))
				   (fboundp (car a))
				   (and (not (featurep 'calc-ext))
					(require 'calc-ext)
					(fboundp (car a))))
			       (apply (car a) args)))))
		(wrong-number-of-arguments
                 (setq math-normalize-error t)
		 (calc-record-why "*Wrong number of arguments"
				  (cons (car a) args))
		 nil)
		(wrong-type-argument
		 (or calc-next-why
                     (calc-record-why "Wrong type of argument"
                                      (cons (car a) args)))
		 nil)
		(args-out-of-range
                 (setq math-normalize-error t)
		 (calc-record-why "*Argument out of range"
                                  (cons (car a) args))
		 nil)
		(inexact-result
		 (calc-record-why "No exact representation for result"
				  (cons (car a) args))
		 nil)
		(math-overflow
                 (setq math-normalize-error t)
		 (calc-record-why "*Floating-point overflow occurred"
				  (cons (car a) args))
		 nil)
		(math-underflow
                 (setq math-normalize-error t)
		 (calc-record-why "*Floating-point underflow occurred"
				  (cons (car a) args))
		 nil)
		(void-variable
                 (setq math-normalize-error t)
		 (if (eq (nth 1 err) 'var-EvalRules)
		     (progn
		       (setq var-EvalRules nil)
		       (math-normalize (cons (car a) args)))
		   (calc-record-why "*Variable is void" (nth 1 err)))))
	      (if (consp (car a))
		  (math-dimension-error)
		(cons (car a) args))))))))



;; True if A is a floating-point real or complex number.  [P x] [Public]
(defun math-floatp (a)
  (cond ((eq (car-safe a) 'float) t)
	((memq (car-safe a) '(cplx polar mod sdev intv))
	 (or (math-floatp (nth 1 a))
	     (math-floatp (nth 2 a))
	     (and (eq (car a) 'intv) (math-floatp (nth 3 a)))))
	((eq (car-safe a) 'date)
	 (math-floatp (nth 1 a)))))



;; Verify that A is a complete object and return A.  [x x] [Public]
(defun math-check-complete (a)
  (cond ((integerp a) a)
	((eq (car-safe a) 'incomplete)
	 (calc-incomplete-error a))
	((consp a) a)
	(t (error "Invalid data object encountered"))))

;; Build a normalized floating-point number.  [F I S]
(defun math-make-float (mant exp)
  (if (eq mant 0)
      '(float 0 0)
    (let* ((ldiff (- calc-internal-prec (math-numdigs mant))))
      (if (< ldiff 0)
	  (setq mant (math-scale-rounding mant ldiff)
		exp (- exp ldiff))))
    (while (= (% mant 10) 0)
      (setq mant (/ mant 10)
	    exp (1+ exp)))
    (if (and (<= exp -4000000)
	     (<= (+ exp (math-numdigs mant) -1) -4000000))
	(signal 'math-underflow nil)
      (if (and (>= exp 3000000)
	       (>= (+ exp (math-numdigs mant) -1) 4000000))
	  (signal 'math-overflow nil)
	(list 'float mant exp)))))

;;; Coerce A to be a float.  [F N; V V] [Public]
(defun math-float (a)
  (cond ((Math-integerp a) (math-make-float a 0))
	((eq (car a) 'frac) (math-div (math-float (nth 1 a)) (nth 2 a)))
	((eq (car a) 'float) a)
	((memq (car a) '(cplx polar vec hms date sdev mod))
	 (cons (car a) (mapcar #'math-float (cdr a))))
	(t (math-float-fancy a))))


(defun math-neg (a)
  (cond ((not (consp a)) (- a))
	((memq (car a) '(frac float))
	 (list (car a) (Math-integer-neg (nth 1 a)) (nth 2 a)))
	((memq (car a) '(cplx vec hms date calcFunc-idn))
	 (cons (car a) (mapcar #'math-neg (cdr a))))
	(t (math-neg-fancy a))))


;;; Compute the number of decimal digits in integer A.  [S I]
(defun math-numdigs (a)
  (cond
   ((= a 0) 0)
   ((progn (when (< a 0) (setq a (- a)))
           (>= a 100))
    (let* ((bd (logb a))
           (d (truncate (/ bd (eval-when-compile (log 10 2))))))
      (let ((b (expt 10 d)))
        (cond
         ((> b a) d)
         ((> (* 10 b) a) (1+ d))
         (t (+ d 2))))))
   ((>= a 10) 2)
   (t 1)))

;;; Multiply (with truncation toward 0) the integer A by 10^N.  [I i S]
(defun math-scale-int (a n)
  (cond ((= n 0) a)
	((> n 0) (math-scale-left a n))
	(t (math-normalize (math-scale-right a (- n))))))

(defun math-scale-left (a n)   ; [I I S]
  (if (= n 0)
      a
    (* a (expt 10 n))))

(defun math-scale-right (a n)   ; [i i S]
  (if (= n 0)
      a
    (if (<= a 0)
	(if (= a 0)
	    0
	  (- (math-scale-right (- a) n)))
      (if (> n 0)
          (/ a (expt 10 n))
        a))))

;;; Multiply (with rounding) the integer A by 10^N.   [I i S]
(defun math-scale-rounding (a n)
  (cond ((>= n 0)
	 (math-scale-left a n))
	(t
	 (if (< a 0)
	     (- (math-scale-rounding (- a) n))
	   (if (= n -1)
	       (/ (+ a 5) 10)
	     (/ (+ (math-scale-right a (- -1 n)) 5) 10))))))


;;; Compute the sum of A and B.  [O O O] [Public]
(defun math-add (a b)
  (or
   (and (not (or (consp a) (consp b)))
        (+ a b))
   (and (Math-zerop a) (not (eq (car-safe a) 'mod))
	(if (and (math-floatp a) (Math-ratp b)) (math-float b) b))
   (and (Math-zerop b) (not (eq (car-safe b) 'mod))
	(if (and (math-floatp b) (Math-ratp a)) (math-float a) a))
   (and (Math-objvecp a) (Math-objvecp b)
	(or
	 (and (Math-ratp a) (Math-ratp b)
	      (require 'calc-ext)
	      (calc-add-fractions a b))
	 (and (Math-realp a) (Math-realp b)
	      (progn
		(or (and (consp a) (eq (car a) 'float))
		    (setq a (math-float a)))
		(or (and (consp b) (eq (car b) 'float))
		    (setq b (math-float b)))
		(math-add-float a b)))
	 (and (require 'calc-ext)
	      (math-add-objects-fancy a b))))
   (and (require 'calc-ext)
	(math-add-symb-fancy a b))))

(defun math-add-float (a b)   ; [F F F]
  (let ((ediff (- (nth 2 a) (nth 2 b))))
    (if (>= ediff 0)
	(if (>= ediff (+ calc-internal-prec calc-internal-prec))
	    a
	  (math-make-float (math-add (nth 1 b)
				     (if (eq ediff 0)
					 (nth 1 a)
				       (math-scale-left (nth 1 a) ediff)))
			   (nth 2 b)))
      (if (>= (setq ediff (- ediff))
	      (+ calc-internal-prec calc-internal-prec))
	  b
	(math-make-float (math-add (nth 1 a)
				   (math-scale-left (nth 1 b) ediff))
			 (nth 2 a))))))

;;; Compute the difference of A and B.  [O O O] [Public]
(defun math-sub (a b)
  (if (or (consp a) (consp b))
      (math-add a (math-neg b))
    (setq a (- a b))
    a))

(defun math-sub-float (a b)   ; [F F F]
  (let ((ediff (- (nth 2 a) (nth 2 b))))
    (if (>= ediff 0)
	(if (>= ediff (+ calc-internal-prec calc-internal-prec))
	    a
	  (math-make-float (math-add (Math-integer-neg (nth 1 b))
				     (if (eq ediff 0)
					 (nth 1 a)
				       (math-scale-left (nth 1 a) ediff)))
			   (nth 2 b)))
      (if (>= (setq ediff (- ediff))
	      (+ calc-internal-prec calc-internal-prec))
	  b
	(math-make-float (math-add (nth 1 a)
				   (Math-integer-neg
				    (math-scale-left (nth 1 b) ediff)))
			 (nth 2 a))))))


;;; Compute the product of A and B.  [O O O] [Public]
(defun math-mul (a b)
  (or
   (and (not (consp a)) (not (consp b))
	(* a b))
   (and (Math-zerop a) (not (eq (car-safe b) 'mod))
	(if (Math-scalarp b)
	    (if (and (math-floatp b) (Math-ratp a)) (math-float a) a)
	  (require 'calc-ext)
	  (math-mul-zero a b)))
   (and (Math-zerop b) (not (eq (car-safe a) 'mod))
	(if (Math-scalarp a)
	    (if (and (math-floatp a) (Math-ratp b)) (math-float b) b)
	  (require 'calc-ext)
	  (math-mul-zero b a)))
   (and (Math-objvecp a) (Math-objvecp b)
	(or
	 (and (Math-ratp a) (Math-ratp b)
	      (require 'calc-ext)
	      (calc-mul-fractions a b))
	 (and (Math-realp a) (Math-realp b)
	      (progn
		(or (and (consp a) (eq (car a) 'float))
		    (setq a (math-float a)))
		(or (and (consp b) (eq (car b) 'float))
		    (setq b (math-float b)))
		(math-make-float (math-mul (nth 1 a) (nth 1 b))
				 (+ (nth 2 a) (nth 2 b)))))
	 (and (require 'calc-ext)
	      (math-mul-objects-fancy a b))))
   (and (require 'calc-ext)
	(math-mul-symb-fancy a b))))

(defun math-infinitep (a &optional undir)
  (while (and (consp a) (memq (car a) '(* / neg)))
    (if (or (not (eq (car a) '*)) (math-infinitep (nth 1 a)))
	(setq a (nth 1 a))
      (setq a (nth 2 a))))
  (and (consp a)
       (eq (car a) 'var)
       (memq (nth 2 a) '(var-inf var-uinf var-nan))
       (if (and undir (eq (nth 2 a) 'var-inf))
	   '(var uinf var-uinf)
	 a)))

;;; Compute the integer (quotient . remainder) of A and B, which may be
;;; small or big integers.  Type and consistency of truncation is undefined
;;; if A or B is negative.  B must be nonzero.  [I.I I I] [Public]
(defun math-idivmod (a b)
  (if (eq b 0)
      (math-reject-arg a "*Division by zero"))
    (cons (/ a b) (% a b)))

(defun math-quotient (a b)   ; [I I I] [Public]
  (if (and (not (consp a)) (not (consp b)))
      (if (= b 0)
	  (math-reject-arg a "*Division by zero")
	(/ a b))))

;;; Compute the quotient of A and B.  [O O N] [Public]
(defun math-div (a b)
  (or
   (and (Math-zerop b)
	(require 'calc-ext)
	(math-div-by-zero a b))
   (and (Math-zerop a) (not (eq (car-safe b) 'mod))
	(if (Math-scalarp b)
	    (if (and (math-floatp b) (Math-ratp a)) (math-float a) a)
	  (require 'calc-ext)
	  (math-div-zero a b)))
   (and (Math-objvecp a) (Math-objvecp b)
	(or
	 (and (Math-integerp a) (Math-integerp b)
	      (let ((q (math-idivmod a b)))
		(if (eq (cdr q) 0)
		    (car q)
		  (if calc-prefer-frac
		      (progn
			(require 'calc-ext)
			(math-make-frac a b))
		    (math-div-float (math-make-float a 0)
				    (math-make-float b 0))))))
	 (and (Math-ratp a) (Math-ratp b)
	      (require 'calc-ext)
	      (calc-div-fractions a b))
	 (and (Math-realp a) (Math-realp b)
	      (progn
		(or (and (consp a) (eq (car a) 'float))
		    (setq a (math-float a)))
		(or (and (consp b) (eq (car b) 'float))
		    (setq b (math-float b)))
		(math-div-float a b)))
	 (and (require 'calc-ext)
	      (math-div-objects-fancy a b))))
   (and (require 'calc-ext)
	(math-div-symb-fancy a b))))

(defun math-div-float (a b)   ; [F F F]
  (let ((ldiff (max (- (1+ calc-internal-prec)
		       (- (math-numdigs (nth 1 a)) (math-numdigs (nth 1 b))))
		    0)))
    (math-make-float (math-quotient (math-scale-int (nth 1 a) ldiff) (nth 1 b))
		     (- (- (nth 2 a) (nth 2 b)) ldiff))))


(defun calcDigit-delchar ()
  (interactive)
  (cond ((looking-at-p " \\+/- \\'")
         (delete-char 5))
	((looking-at-p " mod \\'")
	 (delete-char 5))
	((looking-at-p " \\'")
	 (delete-char 2))
	((eq last-command 'calcDigit-start)
	 (erase-buffer))
	(t (unless (eobp) (delete-char 1))))
  (when (= (calc-minibuffer-size) 0)
    (setq last-command-event 13)
    (calcDigit-nondigit)))


(defvar math-comp-selected)
(defvar calc-selection-cache-entry)
;;; Format the number A as a string.  [X N; X Z] [Public]
(defun math-format-stack-value (entry)
  (setq calc-selection-cache-entry calc-selection-cache-default-entry)
  (let* ((a (car entry))
	 (math-comp-selected (nth 2 entry))
	 (c (cond ((null a) "<nil>")
		  ((eq calc-display-raw t) (format "%s" a))
		  ((stringp a) a)
		  ((eq a 'top-of-stack) (propertize "." 'font-lock-face 'bold))
		  (calc-prepared-composition
		   calc-prepared-composition)
		  ((and (Math-scalarp a)
			(memq calc-language '(nil flat unform))
			(null math-comp-selected))
		   (math-format-number a))
		  (t (require 'calc-ext)
		     (math-compose-expr a 0))))
	 (off (math-stack-value-offset c))
	 s w)
    (and math-comp-selected (setq calc-any-selections t))
    (setq w (cdr off)
	  off (car off))
    (when (> off 0)
      (setq c (math-comp-concat (make-string off ?\s) c)))
    (or (equal calc-left-label "")
	(setq c (math-comp-concat (if (eq a 'top-of-stack)
				      (make-string (length calc-left-label) ?\s)
				    calc-left-label)
				  c)))
    (when calc-line-numbering
      (setq c (math-comp-concat (if (eq calc-language 'big)
				    (if math-comp-selected
					'(tag t "1:  ")
				      "1:  ")
				  "    ")
				c)))
    (unless (or (equal calc-right-label "")
		(eq a 'top-of-stack))
      (require 'calc-ext)
      (setq c (list 'horiz c
		    (make-string (max (- w (math-comp-width c)
					 (length calc-right-label)) 0) ?\s)
		    '(break -1)
		    calc-right-label)))
    (setq s (if (stringp c)
		(if calc-display-raw
		    (prin1-to-string c)
		  c)
	      (math-composition-to-string c w)))
    (when calc-language-output-filter
      (setq s (funcall calc-language-output-filter s)))
    (if (eq calc-language 'big)
	(setq s (concat s "\n"))
      (when calc-line-numbering
	(setq s (concat "1:" (substring s 2)))))
    (setcar (cdr entry) (calc-count-lines s))
    s))

;; The variables math-svo-wid and math-svo-off are local
;; to math-stack-value-offset, but are used by math-stack-value-offset-fancy
;; in calccomp.el.

(defvar math-svo-wid)
(defvar math-svo-off)

(defun math-stack-value-offset (c)
  (let* ((num (if calc-line-numbering 4 0))
	 (math-svo-wid (calc-window-width))
	 math-svo-off)
    (if calc-display-just
	(progn
	  (require 'calc-ext)
	  (math-stack-value-offset-fancy c))
      (setq math-svo-off (or calc-display-origin 0))
      (when (integerp calc-line-breaking)
	(setq math-svo-wid calc-line-breaking)))
    (cons (max (- math-svo-off (length calc-left-label)) 0)
	  (+ math-svo-wid num))))

(defun calc-count-lines (s)
  (let ((pos 0)
	(num 1))
    (while (setq pos (string-search "\n" s pos))
      (setq pos (1+ pos)
	    num (1+ num)))
    num))

(defun math-format-value (a &optional w)
  (if (and (Math-scalarp a)
	   (memq calc-language '(nil flat unform)))
      (math-format-number a)
    (require 'calc-ext)
    (let ((calc-line-breaking nil))
      (math-composition-to-string (math-compose-expr a 0) w))))

(defun calc-window-width ()
  (if calc-embedded-info
      (let ((win (get-buffer-window (aref calc-embedded-info 0))))
	(1- (if win (window-width win) (frame-width))))
    (- (window-width (get-buffer-window (current-buffer)))
       (if calc-line-numbering 5 1))))

(defun math-comp-concat (c1 c2)
  (if (and (stringp c1) (stringp c2))
      (concat c1 c2)
    (list 'horiz c1 c2)))



;;; Format an expression as a one-line string suitable for re-reading.

(defun math-format-flat-expr (a prec)
  (cond
   ((or (not (or (consp a) (integerp a)))
	(eq calc-display-raw t))
    (let ((print-escape-newlines t))
      (concat "'" (prin1-to-string a))))
   ((Math-scalarp a)
    (let ((calc-group-digits nil)
	  (calc-point-char ".")
	  (calc-frac-format (if (> (length (car calc-frac-format)) 1)
				'("::" nil) '(":" nil)))
	  (calc-complex-format nil)
	  (calc-hms-format "%s@ %s' %s\"")
	  (calc-language nil))
      (math-format-number a)))
   (t
    (require 'calc-ext)
    (math-format-flat-expr-fancy a prec))))



;;; Format a number as a string.
(defvar math-half-2-word-size)
(defun math-format-number (a &optional prec)   ; [X N]   [Public]
  (cond
   ((eq calc-display-raw t) (format "%s" a))
   ((and calc-twos-complement-mode
         math-radix-explicit-format
         (Math-integerp a)
         (or (eq a 0)
             (and (Math-integer-posp a)
                  (Math-lessp a math-half-2-word-size))
             (and (Math-integer-negp a)
                  (require 'calc-ext)
                  (let ((comparison
                         (math-compare (Math-integer-neg a) math-half-2-word-size)))
                    (or (= comparison 0)
                        (= comparison -1))))))
    (require 'calc-bin)
    (math-format-twos-complement a))
   ((and (nth 1 calc-frac-format) (Math-integerp a))
    (require 'calc-ext)
    (math-format-number (math-adjust-fraction a)))
   ((integerp a)
    (if (not (or calc-group-digits calc-leading-zeros))
	(if (= calc-number-radix 10)
	    (int-to-string a)
	  (if (< a 0)
	      (concat "-" (math-format-number (- a)))
	    (require 'calc-ext)
	    (if math-radix-explicit-format
		(if calc-radix-formatter
		    (funcall calc-radix-formatter
			     calc-number-radix
			     (if (= calc-number-radix 2)
				 (math-format-binary a)
			       (math-format-radix a)))
		  (format "%d#%s" calc-number-radix
			  (if (= calc-number-radix 2)
			      (math-format-binary a)
			    (math-format-radix a))))
	      (math-format-radix a))))
      (require 'calc-ext)
      (declare-function math--format-integer-fancy "calc-ext" (a))
      (concat (if (< a 0) "-") (math--format-integer-fancy (abs a)))))
   ((stringp a) a)
   ((not (consp a)) (prin1-to-string a))
   ((and (eq (car a) 'float) (= calc-number-radix 10))
    (if (Math-integer-negp (nth 1 a))
	(concat "-" (math-format-number (math-neg a)))
      (let ((mant (nth 1 a))
	    (exp (nth 2 a))
	    (fmt (car calc-float-format))
	    (figs (nth 1 calc-float-format))
	    (point calc-point-char)
	    str)
	(if (and (eq fmt 'fix)
		 (or (and (< figs 0) (setq figs (- figs)))
		     (> (+ exp (math-numdigs mant)) (- figs))))
	    (progn
	      (setq mant (math-scale-rounding mant (+ exp figs))
		    str (int-to-string mant))
	      (if (<= (length str) figs)
		  (setq str (concat (make-string (1+ (- figs (length str))) ?0)
				    str)))
	      (if (> figs 0)
		  (setq str (concat (substring str 0 (- figs)) point
				    (substring str (- figs))))
		(setq str (concat str point)))
	      (when calc-group-digits
		(require 'calc-ext)
		(setq str (math-group-float str))))
	  (when (< figs 0)
	    (setq figs (+ calc-internal-prec figs)))
	  (when (> figs 0)
	    (let ((adj (- figs (math-numdigs mant))))
	      (when (< adj 0)
		(setq mant (math-scale-rounding mant adj)
		      exp (- exp adj)))))
	  (setq str (int-to-string mant))
	  (let* ((len (length str))
		 (dpos (+ exp len))
                 (trailing-0 (and calc-digit-after-point "0")))
	    (if (and (eq fmt 'float)
		     (<= dpos (+ calc-internal-prec calc-display-sci-high))
		     (>= dpos (+ calc-display-sci-low 2)))
		(progn
		  (cond
		   ((= dpos 0)
		    (setq str (concat "0" point str)))
		   ((and (<= exp 0) (> dpos 0))
		    (setq str (concat (substring str 0 dpos) point
				      (substring str dpos)
                                      (and (>= dpos len) trailing-0))))
		   ((> exp 0)
		    (setq str (concat str (make-string exp ?0)
                                      point trailing-0)))
		   (t   ; (< dpos 0)
		    (setq str (concat "0" point
				      (make-string (- dpos) ?0) str))))
		  (when calc-group-digits
		    (require 'calc-ext)
		    (setq str (math-group-float str))))
	      (let* ((eadj (+ exp len))
		     (scale (if (eq fmt 'eng)
				(1+ (math-mod (+ eadj 300002) 3))
			      1)))
		(if (> scale (length str))
		    (setq str (concat str (make-string (- scale (length str))
						       ?0))))
		(if (< scale (length str))
		    (setq str (concat (substring str 0 scale) point
				      (substring str scale))))
		(when calc-group-digits
		  (require 'calc-ext)
		  (setq str (math-group-float str)))
		(setq str (format (if (memq calc-language '(math maple))
				      (if (and prec (> prec 191))
					  "(%s*10.^%d)" "%s*10.^%d")
				    "%se%d")
				  str (- eadj scale)))))))
	str)))
   (t
    (require 'calc-ext)
    (math-format-number-fancy a prec))))

;;; Parse a simple number in string form.   [N X] [Public]
(defun math-read-number (s &optional decimal)
  "Convert the string S into a Calc number."
  (math-normalize
   (save-match-data
     (cond

      ;; Integers (most common case)
      ((string-match "\\` *\\([0-9]+\\) *\\'" s)
       (let ((digs (math-match-substring s 1)))
         (if (and (memq calc-language calc-lang-c-type-hex)
                  (> (length digs) 1)
                  (eq (aref digs 0) ?0)
                  (null decimal))
             (math-read-number (concat "8#" digs))
           (string-to-number digs))))

      ;; Clean up the string if necessary
      ((string-match "\\`\\(.*\\)[ \t\n]+\\([^\001]*\\)\\'" s)
       (math-read-number (concat (math-match-substring s 1)
                                 (math-match-substring s 2))))

      ;; Plus and minus signs
      ((string-match "^[-_+]\\(.*\\)$" s)
       (let ((val (math-read-number (math-match-substring s 1))))
         (and val (if (eq (aref s 0) ?+) val (math-neg val)))))

      ;; Forms that require extensions module
      ((string-match "[^-+0-9eE.]" s)
       (require 'calc-ext)
       (math-read-number-fancy s))

      ;; Decimal point
      ((string-match "^\\([0-9]*\\)\\.\\([0-9]*\\)$" s)
       (let ((int (math-match-substring s 1))
             (frac (math-match-substring s 2)))
         (let ((ilen (length int))
               (flen (length frac)))
           (let ((int (if (> ilen 0) (math-read-number int t) 0))
                 (frac (if (> flen 0) (math-read-number frac t) 0)))
             (and int frac (or (> ilen 0) (> flen 0))
                  (list 'float
                        (math-add (math-scale-int int flen) frac)
                        (- flen)))))))

      ;; "e" notation
      ((string-match "^\\(.*\\)[eE]\\([-+]?[0-9]+\\)$" s)
       (let ((mant (math-match-substring s 1))
             (exp (math-match-substring s 2)))
         (let ((mant (if (> (length mant) 0) (math-read-number mant t) 1))
               (exp (if (<= (length exp) (if (memq (aref exp 0) '(?+ ?-)) 8 7))
                        (string-to-number exp))))
           (and mant exp (Math-realp mant) (> exp -4000000) (< exp 4000000)
                (let ((mant (math-float mant)))
                  (list 'float (nth 1 mant) (+ (nth 2 mant) exp)))))))

      ;; Syntax error!
      (t nil)))))

;;; Parse a very simple number, keeping all digits.
(defun math-read-number-simple (s)
  "Convert the string S into a Calc number.
S is assumed to be a simple number (integer or float without an exponent)
and all digits are kept, regardless of Calc's current precision."
  (save-match-data
    (cond
     ;; Integer
     ((string-match "^[0-9]+$" s)
      (if (string-match "^\\(0+\\)" s)
          (setq s (substring s (match-end 0))))
      (string-to-number s))
     ;; Minus sign
     ((string-match "^-[0-9]+$" s)
      (string-to-number s))
     ;; Decimal point
     ((string-match "^\\(-?[0-9]*\\)\\.\\([0-9]*\\)$" s)
      (let ((int (math-match-substring s 1))
            (frac (math-match-substring s 2)))
        (list 'float (math-read-number-simple (concat int frac))
              (- (length frac)))))
     ;; Syntax error!
     (t nil))))

(defun math-match-substring (s n)
  (if (match-beginning n)
      (substring s (match-beginning n) (match-end n))
    ""))

(defconst math-standard-opers
  '( ( "_"     calcFunc-subscr 1200 1201 )
     ( "%"     calcFunc-percent 1100 -1 )
     ( "u!"    calcFunc-lnot -1 1000 )
     ( "mod"   mod	     400 400 185 )
     ( "+/-"   sdev	     300 300 185 )
     ( "!!"    calcFunc-dfact 210 -1 )
     ( "!"     calcFunc-fact 210  -1 )
     ( "^"     ^             201 200 )
     ( "**"    ^             201 200 )
     ( "u+"    ident	     -1  197 )
     ( "u-"    neg	     -1  197 )
     ( "/"     /             190 191 )
     ( "%"     %             190 191 )
     ( "\\"    calcFunc-idiv 190 191 )
     ( "+"     +	     180 181 )
     ( "-"     -	     180 181 )
     ( "|"     |	     170 171 )
     ( "<"     calcFunc-lt   160 161 )
     ( ">"     calcFunc-gt   160 161 )
     ( "<="    calcFunc-leq  160 161 )
     ( ">="    calcFunc-geq  160 161 )
     ( "="     calcFunc-eq   160 161 )
     ( "=="    calcFunc-eq   160 161 )
     ( "!="    calcFunc-neq  160 161 )
     ( "&&"    calcFunc-land 110 111 )
     ( "||"    calcFunc-lor  100 101 )
     ( "?"     (math-read-if) 91  90 )
     ( "!!!"   calcFunc-pnot  -1  85 )
     ( "&&&"   calcFunc-pand  80  81 )
     ( "|||"   calcFunc-por   75  76 )
     ( ":="    calcFunc-assign 51 50 )
     ( "::"    calcFunc-condition 45 46 )
     ( "=>"    calcFunc-evalto 40 41 )
     ( "=>"    calcFunc-evalto 40 -1 )))

(defun math-standard-ops ()
  (if calc-multiplication-has-precedence
      (cons
       '( "*"     *             196 195 )
       (cons
        '( "2x"    *             196 195 )
        math-standard-opers))
    (cons
     '( "*"     *             190 191 )
     (cons
      '( "2x"    *             190 191 )
      math-standard-opers))))

(defvar math-expr-opers (math-standard-ops))

(defun math-standard-ops-p ()
  (let ((meo (caar math-expr-opers)))
    (and (stringp meo)
         (string= meo "*"))))

(defun math-expr-ops ()
  (if (math-standard-ops-p)
      (math-standard-ops)
    math-expr-opers))

;;;###autoload
(defun calc-grab-region (top bot arg)
  "Parse the region as a vector of numbers and push it on the Calculator stack."
  (interactive "r\nP")
  (require 'calc-ext)
  (if rectangle-mark-mode
      (calc-do-grab-rectangle top bot arg)
    (calc-do-grab-region top bot arg)))

;;;###autoload
(defun calc-grab-rectangle (top bot arg)
  "Parse a rectangle as a matrix of numbers and push it on the Calculator stack."
  (interactive "r\nP")
  (require 'calc-ext)
  (calc-do-grab-rectangle top bot arg))

;;;###autoload
(defun calc-grab-sum-down (top bot arg)
  "Parse a rectangle as a matrix of numbers and sum its columns."
  (interactive "r\nP")
  (require 'calc-ext)
  (calc-do-grab-rectangle top bot arg 'calcFunc-reduced))

;;;###autoload
(defun calc-grab-sum-across (top bot arg)
  "Parse a rectangle as a matrix of numbers and sum its rows."
  (interactive "r\nP")
  (require 'calc-ext)
  (calc-do-grab-rectangle top bot arg 'calcFunc-reducea))


;;;###autoload
(defun calc-embedded (arg &optional end obeg oend)
  "Start Calc Embedded mode on the formula surrounding point."
  (interactive "P")
  (require 'calc-ext)
  (calc-do-embedded arg end obeg oend))

;;;###autoload
(defun calc-embedded-activate (&optional arg cbuf)
  "Scan the current editing buffer for all embedded := and => formulas.
Also looks for the equivalent TeX words, \\gets and \\evalto."
  (interactive "P")
  (calc-do-embedded-activate arg cbuf))

(defun calc-user-invocation ()
  (interactive)
  (unless calc-invocation-macro
    (error "Use `Z I' inside Calc to define a `C-x * Z' keyboard macro"))
  (execute-kbd-macro calc-invocation-macro nil))

;;; User-programmability.

;;;###autoload
(defmacro defmath (func args &rest body)   ;  [Public]
  "Define Calc function.

Like `defun' except that code in the body of the definition can
make use of the full range of Calc data types and the usual
arithmetic operations are converted to their Calc equivalents.

The prefix `calcFunc-' is added to the specified name to get the
actual Lisp function name.

See Info node `(calc)Defining Functions'."
  (declare (doc-string 3) (indent defun)) ;; FIXME: Edebug spec?
  (require 'calc-ext)
  (math-do-defmath func args body))

(defun calc-read-key (&optional _optkey)
  (declare (obsolete read-event "27.1"))
  (let ((key (read-event)))
    (cons key key)))

(defun calc-unread-command (&optional input)
  (let ((event (or input last-command-event)))
    ;; Avoid recording twice the keys pressed while defining a
    ;; keyboard macro.
    (when defining-kbd-macro
      (setq event (cons 'no-record event)))
    (push event unread-command-events)))

(defun calc-clear-unread-commands ()
  (setq unread-command-events nil))

(defcalcmodevar math-2-word-size 4294967296
  "Two to the power of `calc-word-size'.")

(defcalcmodevar math-half-2-word-size 2147483648
  "One-half of two to the power of `calc-word-size'.")

(when calc-always-load-extensions
  (require 'calc-ext)
  (calc-load-everything))


(run-hooks 'calc-load-hook)

(provide 'calc)

;;; calc.el ends here
