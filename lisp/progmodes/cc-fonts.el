;; cc-fonts.el --- font lock support for CC Mode -*- lexical-binding: t -*-

;; Copyright (C) 2002-2025 Free Software Foundation, Inc.

;; Authors:    2003- Alan Mackenzie
;;             2002- Martin Stjernholm
;; Maintainer: bug-cc-mode@gnu.org
;; Created:    07-Jan-2002
;; Keywords:   c languages
;; Package:    cc-mode

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

;; Some comments on the use of faces:
;;
;; o  `c-label-face-name' is either `font-lock-constant-face' (in
;;    Emacs), or `font-lock-reference-face'.
;;
;; o  `c-constant-face-name', `c-reference-face-name' and
;;    `c-doc-markup-face-name' are essentially set up like
;;    `c-label-face-name'.
;;
;; o  `c-preprocessor-face-name' is `font-lock-preprocessor-face' in
;;    XEmacs and - in lack of a closer equivalent -
;;    `font-lock-builtin-face' or `font-lock-reference-face' in Emacs.
;;
;; o  `c-doc-face-name' is `font-lock-doc-string-face' in XEmacs,
;;    `font-lock-doc-face' in Emacs 21 and later, or
;;    `font-lock-comment-face' in older Emacs (that since source
;;    documentation are actually comments in these languages, as opposed
;;    to elisp).
;;
;; TBD: We should probably provide real faces for the above uses and
;; instead initialize them from the standard faces.

;;; Code:

;; The faces that already have been put onto the text is tested in
;; various places to direct further fontifications.  For this to work,
;; the following assumptions regarding the faces must hold (apart from
;; the dependencies on the font locking order):
;;
;; o  `font-lock-comment-face' and the face in `c-doc-face-name' is
;;    not used in anything but comments.
;; o  If any face (e.g. `c-doc-markup-face-name') but those above is
;;    used in comments, it doesn't replace them.
;; o  `font-lock-string-face' is not used in anything but string
;;    literals (single or double quoted).
;; o  `font-lock-keyword-face' and the face in `c-label-face-name' are
;;    never overlaid with other faces.

(eval-when-compile
  (let ((load-path
	 (if (and (boundp 'byte-compile-dest-file)
		  (stringp byte-compile-dest-file))
	     (cons (file-name-directory byte-compile-dest-file) load-path)
	   load-path)))
    (load "cc-bytecomp" nil t)))

(cc-require 'cc-defs)
(cc-require-when-compile 'cc-langs)
(cc-require 'cc-vars)
(cc-require 'cc-engine)

;; Avoid repeated loading through the eval-after-load directive in
;; cc-mode.el.
(provide 'cc-fonts)

(cc-external-require 'font-lock)

(cc-bytecomp-defvar parse-sexp-lookup-properties) ; Emacs only.

(declare-function cl-set-difference "cl-seq" (cl-list1 cl-list2 &rest cl-keys))
(declare-function cl-delete-duplicates "cl-seq" (seq &rest cl-keys))

;; Need to declare these local symbols during compilation since
;; they're referenced from lambdas in `byte-compile' calls that are
;; executed at compile time.  They don't need to have the proper
;; definitions, though, since the generated functions aren't called
;; during compilation.
(cc-bytecomp-defvar c-preprocessor-face-name)
(cc-bytecomp-defvar c-reference-face-name)
(cc-bytecomp-defvar c-block-comment-flag)
(cc-bytecomp-defun c-fontify-recorded-types-and-refs)
(cc-bytecomp-defun c-font-lock-declarators)
(cc-bytecomp-defun c-font-lock-objc-method)
(cc-bytecomp-defun c-font-lock-invalid-string)
(cc-bytecomp-defun c-font-lock-fontify-region)

(cc-bytecomp-defvar font-lock-reference-face) ; For Emacs 29


;; Note that font-lock in XEmacs doesn't expand face names as
;; variables, so we have to use the (eval . FORM) in the font lock
;; matchers wherever we use these alias variables.

(defconst c-preprocessor-face-name
  (cond ((c-face-name-p 'font-lock-preprocessor-face)
	 ;; XEmacs has a font-lock-preprocessor-face.
	 'font-lock-preprocessor-face)
	((c-face-name-p 'font-lock-builtin-face)
	 ;; In Emacs font-lock-builtin-face has traditionally been
	 ;; used for preprocessor directives.
	 'font-lock-builtin-face)
	((and (c-face-name-p 'font-lock-reference-face)
	      (boundp 'font-lock-reference-face)
	      (eq font-lock-reference-face 'font-lock-reference-face))
	 'font-lock-reference-face)
	(t 'font-lock-constant-face)))

(defconst c-label-face-name
  (cond ((c-face-name-p 'font-lock-label-face)
	 ;; If it happens to occur in the future.  (Well, the more
	 ;; pragmatic reason is to get unique faces for the test
	 ;; suite.)
	 'font-lock-label-face)
	((and (c-face-name-p 'font-lock-constant-face)
	      (boundp 'font-lock-constant-face)
	      (eq font-lock-constant-face 'font-lock-constant-face))
	 ;; Test both if font-lock-constant-face exists and that it's
	 ;; not an alias for something else.  This is important since
	 ;; we compare already set faces in various places.
	 'font-lock-constant-face)
	(t
	 'font-lock-reference-face)))

(defconst c-constant-face-name
  (if (and (c-face-name-p 'font-lock-constant-face)
	   (boundp 'font-lock-constant-face)
	   (eq font-lock-constant-face 'font-lock-constant-face))
      ;; This doesn't exist in some earlier versions of XEmacs 21.
      'font-lock-constant-face
    c-label-face-name))

(defconst c-reference-face-name
  (cond
   ((and (c-face-name-p 'font-lock-reference-face)
	   (boundp 'font-lock-reference-face)
	   (eq font-lock-reference-face 'font-lock-reference-face))
    ;; This is considered obsolete in Emacs, but it still maps well
    ;; to this use.  (Another reason to do this is to get unique
    ;; faces for the test suite.)
    'font-lock-reference-face)
   ((c-face-name-p 'font-lock-constant-face)
    'font-lock-constant-face)
   (t c-label-face-name)))

;; This should not mapped to a face that also is used to fontify things
;; that aren't comments or string literals.
(defconst c-doc-face-name
  (cond ((c-face-name-p 'font-lock-doc-string-face)
	 ;; XEmacs.
	 'font-lock-doc-string-face)
	((c-face-name-p 'font-lock-doc-face)
	 ;; Emacs 21 and later.
	 'font-lock-doc-face)
	(t
	 'font-lock-comment-face)))

(defconst c-doc-markup-face-name
  (if (c-face-name-p 'font-lock-doc-markup-face)
	 ;; Exists in Emacs 28+.  (For other emacsen, the pragmatic
	 ;; reason is to get unique faces for the test suite.)
	 'font-lock-doc-markup-face
    c-label-face-name))

(defconst c-negation-char-face-name
  (if (c-face-name-p 'font-lock-negation-char-face)
      ;; Emacs 22 has a special face for negation chars.
      'font-lock-negation-char-face))

(cc-bytecomp-defun face-inverse-video-p) ; Only in Emacs.

(defun c-make-inverse-face (oldface newface)
  ;; Emacs and XEmacs have completely different face manipulation
  ;; routines. :P
  (copy-face oldface newface)
  (cond ((fboundp 'face-inverse-video-p)
	 ;; Emacs.  This only looks at the inverse flag in the current
	 ;; frame.  Other display configurations might be different,
	 ;; but it can only show if the same Emacs has frames on
	 ;; e.g. a color and a monochrome display simultaneously.
	 (unless (face-inverse-video-p oldface)
	   (invert-face newface)))
	((fboundp 'face-property-instance)
	 ;; XEmacs.  Same pitfall here.
	 (unless (face-property-instance oldface 'reverse)
	   (invert-face newface)))))

(defvar c-annotation-face 'c-annotation-face)

(defface c-annotation-face
  '((default :inherit font-lock-constant-face))
  "Face for highlighting annotations in Java mode and similar modes."
  :version "24.1"
  :group 'c)

(eval-and-compile
  ;; We need the following definitions during compilation since they're
  ;; used when the `c-lang-defconst' initializers are evaluated.  Define
  ;; them at runtime too for the sake of derived modes.

  ;; This indicates the "font locking context", and is set just before
  ;; fontification is done.  If non-nil, it says, e.g., point starts
  ;; from within a #if preprocessor construct.
  (defvar c-font-lock-context nil)
  (make-variable-buffer-local 'c-font-lock-context)

  (defmacro c-put-font-lock-face (from to face)
    ;; Put a face on a region (overriding any existing face) in the way
    ;; font-lock would do it.  In XEmacs that means putting an
    ;; additional font-lock property, or else the font-lock package
    ;; won't recognize it as fontified and might override it
    ;; incorrectly.
    ;;
    ;; This function does a hidden buffer change.
    (declare (debug t))
    (if (fboundp 'font-lock-set-face)
	;; Note: This function has no docstring in XEmacs so it might be
	;; considered internal.
	`(font-lock-set-face ,from ,to ,face)
      `(put-text-property ,from ,to 'face ,face)))

  (defmacro c-remove-font-lock-face (from to)
    ;; This is the inverse of `c-put-font-lock-face'.
    ;;
    ;; This function does a hidden buffer change.
    (declare (debug t))
    (if (fboundp 'font-lock-remove-face)
	`(font-lock-remove-face ,from ,to)
      `(remove-text-properties ,from ,to '(face nil))))

  (defmacro c-put-font-lock-string-face (from to)
    ;; Put `font-lock-string-face' on a string.  The surrounding
    ;; quotes are included in Emacs but not in XEmacs.  The passed
    ;; region should include them.
    ;;
    ;; This function does a hidden buffer change.
    (declare (debug t))
    (if (featurep 'xemacs)
	`(c-put-font-lock-face (1+ ,from) (1- ,to) 'font-lock-string-face)
      `(c-put-font-lock-face ,from ,to 'font-lock-string-face)))

  (defmacro c-fontify-types-and-refs (varlist &rest body)
    (declare (indent 1) (debug let*))
    ;; Like `let*', but additionally activates `c-record-type-identifiers'
    ;; and `c-record-ref-identifiers', and fontifies the recorded ranges
    ;; accordingly on exit.
    ;;
    ;; This function does hidden buffer changes.
    `(let* ((c-record-type-identifiers t)
	    c-record-ref-identifiers
	    ,@varlist)
       (prog1 (progn ,@body)
	 (c-fontify-recorded-types-and-refs))))

  (defun c-skip-comments-and-strings (limit)
    ;; If the point is within a region fontified as a comment or
    ;; string literal skip to the end of it or to LIMIT, whichever
    ;; comes first, and return t.  Otherwise return nil.  The match
    ;; data is not clobbered.
    ;;
    ;; This function might do hidden buffer changes.
    (when (c-got-face-at (point) c-literal-faces)
      (while (progn
	       (goto-char (c-next-single-property-change
			   (point) 'face nil limit))
	       (and (< (point) limit)
		    (c-got-face-at (point) c-literal-faces))))
      t))

  (defun c-make-syntactic-matcher (regexp)
    ;; Returns a byte compiled function suitable for use in place of a
    ;; regexp string in a `font-lock-keywords' matcher, except that
    ;; only matches outside comments and string literals count.
    ;;
    ;; This function does not do any hidden buffer changes, but the
    ;; generated functions will.  (They are however used in places
    ;; covered by the font-lock context.)
    (byte-compile
     `(lambda (limit)
	(let (res)
	  (c-skip-comments-and-strings limit)
	  (while (and (setq res (re-search-forward ,regexp limit t))
		      (progn
			(goto-char (match-beginning 0))
			(or (c-skip-comments-and-strings limit)
			    (progn
			      (goto-char (match-end 0))
			      nil)))))
	  res))))

  (defun c-make-font-lock-search-form (regexp highlights &optional check-point)
    ;; Return a lisp form which will fontify every occurrence of REGEXP
    ;; (a regular expression, NOT a function) between POINT and `limit'
    ;; with HIGHLIGHTS, a list of highlighters as specified on page
    ;; "Search-based Fontification" in the elisp manual.  If CHECK-POINT
    ;; is non-nil, we will check (< (point) limit) in the main loop.
    `(progn
       (c-skip-comments-and-strings limit)
       (while
	   ,(if check-point
		`(and (< (point) limit)
		      (re-search-forward ,regexp limit t))
	      `(re-search-forward ,regexp limit t))
	 (unless (progn
		   (goto-char (match-beginning 0))
		   (c-skip-comments-and-strings limit))
	   (goto-char (match-end 0))
	   ,@(mapcar
	      (lambda (highlight)
		(if (integerp (car highlight))
		    ;; e.g. highlight is (1 font-lock-type-face t)
		    (progn
		      (unless (eq (nth 2 highlight) t)
			(error
			 "The override flag must currently be t in %s"
			 highlight))
		      (when (nth 3 highlight)
			(error
			 "The laxmatch flag may currently not be set in %s"
			 highlight))
		      `(save-match-data
			 (c-put-font-lock-face
			  (match-beginning ,(car highlight))
			  (match-end ,(car highlight))
			  ,(elt highlight 1))))
		  ;; highlight is an "ANCHORED HIGHLIGHTER" of the form
		  ;; (ANCHORED-MATCHER PRE-FORM POST-FORM SUBEXP-HIGHLIGHTERS...)
		  (when (nth 3 highlight)
		    (error "Match highlights currently not supported in %s"
			   highlight))
		  `(progn
		     ,(nth 1 highlight)
		     (save-match-data ,(car highlight))
		     ,(nth 2 highlight))))
	      highlights)))))

  (defun c-make-font-lock-search-function (regexp &rest highlights)
    ;; This function makes a byte compiled function that works much like
    ;; a matcher element in `font-lock-keywords'.  It cuts out a little
    ;; bit of the overhead compared to a real matcher.  The main reason
    ;; is however to pass the real search limit to the anchored
    ;; matcher(s), since most (if not all) font-lock implementations
    ;; arbitrarily limit anchored matchers to the same line, and also
    ;; to insulate against various other irritating differences between
    ;; the different (X)Emacs font-lock packages.
    ;;
    ;; REGEXP is the matcher, which must be a regexp.  Only matches
    ;; where the beginning is outside any comment or string literal are
    ;; significant.
    ;;
    ;; HIGHLIGHTS is a list of highlight specs, just like in
    ;; `font-lock-keywords', with these limitations: The face is always
    ;; overridden (no big disadvantage, since hits in comments etc are
    ;; filtered anyway), there is no "laxmatch", and an anchored matcher
    ;; is always a form which must do all the fontification directly.
    ;; `limit' is a variable bound to the real limit in the context of
    ;; the anchored matcher forms.
    ;;
    ;; This function does not do any hidden buffer changes, but the
    ;; generated functions will.  (They are however used in places
    ;; covered by the font-lock context.)

    ;; Note: Replace `byte-compile' with `eval' to debug the generated
    ;; lambda more easily.
    (byte-compile
     `(lambda (limit)
	(let ( ;; The font-lock package in Emacs is known to clobber
	      ;; `parse-sexp-lookup-properties' (when it exists).
	      (parse-sexp-lookup-properties
	       (cc-eval-when-compile
		 (boundp 'parse-sexp-lookup-properties))))
	  ,(c-make-font-lock-search-form regexp highlights t))
	nil)))

  (defun c-make-font-lock-BO-decl-search-function (regexp &rest highlights)
    ;; This function makes a byte compiled function that first moves back
    ;; to the beginning of the current declaration (if any), then searches
    ;; forward for matcher elements (as in `font-lock-keywords') and
    ;; fontifies them.
    ;;
    ;; The motivation for moving back to the declaration start is to
    ;; establish a context for the current text when, e.g., a character
    ;; is typed on a C++ inheritance continuation line, or a jit-lock
    ;; chunk starts there.
    ;;
    ;; The new function works much like a matcher element in
    ;; `font-lock-keywords'.  It cuts out a little bit of the overhead
    ;; compared to a real matcher.  The main reason is however to pass the
    ;; real search limit to the anchored matcher(s), since most (if not
    ;; all) font-lock implementations arbitrarily limit anchored matchers
    ;; to the same line, and also to insulate against various other
    ;; irritating differences between the different (X)Emacs font-lock
    ;; packages.
    ;;
    ;; REGEXP is the matcher, which must be a regexp.  Only matches
    ;; where the beginning is outside any comment or string literal are
    ;; significant.
    ;;
    ;; HIGHLIGHTS is a list of highlight specs, just like in
    ;; `font-lock-keywords', with these limitations: The face is always
    ;; overridden (no big disadvantage, since hits in comments etc are
    ;; filtered anyway), there is no "laxmatch", and an anchored matcher
    ;; is always a form which must do all the fontification directly.
    ;; `limit' is a variable bound to the real limit in the context of
    ;; the anchored matcher forms.
    ;;
    ;; This function does not do any hidden buffer changes, but the
    ;; generated functions will.  (They are however used in places
    ;; covered by the font-lock context.)

    ;; Note: Replace `byte-compile' with `eval' to debug the generated
    ;; lambda more easily.
    (byte-compile
     `(lambda (limit)
	(let ((lit-start (c-literal-start)))
	  (when lit-start (goto-char lit-start)))
	(let ( ;; The font-lock package in Emacs is known to clobber
	      ;; `parse-sexp-lookup-properties' (when it exists).
	      (parse-sexp-lookup-properties
	       (cc-eval-when-compile
		 (boundp 'parse-sexp-lookup-properties)))
	      (BOD-limit
	       (c-determine-limit 1000)))
	  (goto-char
	   (let ((here (point)))
	     (if (eq (car (c-beginning-of-decl-1 BOD-limit)) 'same)
		 (point)
	       here)))
	  ,(c-make-font-lock-search-form regexp highlights))
	nil)))

  (defun c-make-font-lock-context-search-function (normal &rest state-stanzas)
    ;; This function makes a byte compiled function that works much like
    ;; a matcher element in `font-lock-keywords', with the following
    ;; enhancement: the generated function will test for particular "font
    ;; lock contexts" at the start of the region, i.e. is this point in
    ;; the middle of some particular construct?  if so the generated
    ;; function will first fontify the tail of the construct, before
    ;; going into the main loop and fontify full constructs up to limit.
    ;;
    ;; The generated function takes one parameter called `limit', and
    ;; will fontify the region between POINT and LIMIT.
    ;;
    ;; NORMAL is a list of the form (REGEXP HIGHLIGHTS .....), and is
    ;; used to fontify the "regular" bit of the region.
    ;; STATE-STANZAS is list of elements of the form (STATE LIM REGEXP
    ;; HIGHLIGHTS), each element coding one possible font lock context.

    ;; o - REGEXP is a font-lock regular expression (NOT a function),
    ;; o - HIGHLIGHTS is a list of zero or more highlighters as defined
    ;;   on page "Search-based Fontification" in the elisp manual.  As
    ;;   yet (2009-06), they must have OVERRIDE set, and may not have
    ;;   LAXMATCH set.
    ;;
    ;; o - STATE is the "font lock context" (e.g. in-cpp-expr) and is
    ;;   not quoted.
    ;; o - LIM is a lisp form whose evaluation will yield the limit
    ;;   position in the buffer for fontification by this stanza.
    ;;
    ;; This function does not do any hidden buffer changes, but the
    ;; generated functions will.  (They are however used in places
    ;; covered by the font-lock context.)
    ;;
    ;; Note: Replace `byte-compile' with `eval' to debug the generated
    ;; lambda more easily.
    (byte-compile
     `(lambda (limit)
	(let ( ;; The font-lock package in Emacs is known to clobber
	      ;; `parse-sexp-lookup-properties' (when it exists).
	      (parse-sexp-lookup-properties
	       (cc-eval-when-compile
		 (boundp 'parse-sexp-lookup-properties))))
	  ,@(mapcar
	     (lambda (stanza)
	       (let ((state (car stanza))
		     (lim (nth 1 stanza))
		     (regexp (nth 2 stanza))
		     (highlights (cdr (cddr stanza))))
		 `(if (eq c-font-lock-context ',state)
		      (let ((limit ,lim))
			,(c-make-font-lock-search-form
			  regexp highlights)))))
	     state-stanzas)
	  ;; In the next form, check that point hasn't been moved beyond
	  ;; `limit' in any of the above stanzas.
	  ,(c-make-font-lock-search-form (car normal) (cdr normal) t)
	  nil)))))

(defun c-fontify-recorded-types-and-refs ()
  ;; Convert the ranges recorded on `c-record-type-identifiers' and
  ;; `c-record-ref-identifiers' to fontification.
  ;;
  ;; This function does hidden buffer changes.
  (let (elem)
    (while (consp c-record-type-identifiers)
      (setq elem (car c-record-type-identifiers)
	    c-record-type-identifiers (cdr c-record-type-identifiers))
      (c-put-font-lock-face (car elem) (cdr elem)
			    'font-lock-type-face))
    (while c-record-ref-identifiers
      (setq elem (car c-record-ref-identifiers)
	    c-record-ref-identifiers (cdr c-record-ref-identifiers))
      ;; Note that the reference face is a variable that is
      ;; dereferenced, since it's an alias in Emacs.
      (c-put-font-lock-face (car elem) (cdr elem)
			    c-reference-face-name))))

(defun c-font-lock-cpp-messages (limit)
  ;; Font lock #error and #warning messages between point and LIMIT.
  ;; Always return nil to prevent a further call to this function.
  ;; The position of point at the end of this function is random.
  (while
      (and (< (point) limit)
	   (re-search-forward c-cpp-messages-re limit t))
    (let ((beg (match-beginning c-cpp-message-match-no))
	  (end (match-end c-cpp-message-match-no)))
      ;; Don't use c-put-font-lock-string-face here, since in XEmacs that
      ;; would fail to fontify the first and last characters - We don't have
      ;; any string delimiters in this construction.
      (c-put-font-lock-face beg end 'font-lock-string-face)
      ;; We replace '(1) (punctuation) syntax-table text properties on ' by
      ;; '(3) (symbol), so that these characters won't later get the warning
      ;; face.
      (goto-char beg)
      (while (and
	      (< (point) end)
	      (c-search-forward-char-property-with-value-on-char
	       'syntax-table '(1) ?\' end))
	(c-put-char-property ;; -trim-caches
			    (1- (point)) 'syntax-table '(3)))
      (goto-char end)))
  nil)

(c-lang-defconst c-cpp-matchers
  "Font lock matchers for preprocessor directives and purely lexical
stuff.  Used on level 1 and higher."

  ;; Note: `c-font-lock-declarations' assumes that no matcher here
  ;; sets `font-lock-type-face' in languages where
  ;; `c-recognize-<>-arglists' is set.

  t `(;; Fontify "invalid" comment delimiters
      ,@(when (and (c-lang-const c-block-comment-starter)
		   (c-lang-const c-line-comment-starter))
	  `(c-maybe-font-lock-wrong-style-comments))
      ,@(when (c-lang-const c-opt-cpp-prefix)
	  (let* ((noncontinued-line-end "\\(\\=\\|\\(\\=\\|[^\\]\\)[\n\r]\\)")
		 (ncle-depth (regexp-opt-depth noncontinued-line-end))
		 (sws-depth (c-lang-const c-syntactic-ws-depth))
		 (nsws-depth (c-lang-const c-nonempty-syntactic-ws-depth)))

	    `(;; The stuff after #error and #warning is a message, so
	      ;; fontify it as a string.
	      ,@(when (c-lang-const c-cpp-message-directives)
		  '(c-font-lock-cpp-messages))

	      ;; Fontify filenames in #include <...> as strings.
	      ,@(when (c-lang-const c-cpp-include-directives)
		  ;; We used to use a font-lock "anchored matcher" here for
		  ;; the paren syntax.  This failed when the ">" was at EOL,
		  ;; since `font-lock-fontify-anchored-keywords' terminated
		  ;; its loop at EOL without executing our lambda form at all.
		  ;; (2024-10): The paren syntax is now handled in
		  ;; before/after-change functions.
		  `((,(concat noncontinued-line-end
			      "\\("	; To make the next ^ special.
			      (c-lang-const c-cpp-include-key)
			      "\\)"
			      (c-lang-const c-syntactic-ws)
			      "\\(<\\([^>\n\r]*\\)>?\\)")
		     ,(+ ncle-depth 1
			 (regexp-opt-depth (c-lang-const c-cpp-include-key))
			 sws-depth
			 (if (featurep 'xemacs) 2 1))
		     font-lock-string-face t)))

	      ;; #define.
	      ,@(when (c-lang-const c-opt-cpp-macro-define)
		  `((,(c-make-font-lock-search-function
		       (concat
			noncontinued-line-end
			(c-lang-const c-opt-cpp-prefix)
			(c-lang-const c-opt-cpp-macro-define)
			(c-lang-const c-nonempty-syntactic-ws)
			"\\(" (c-lang-const ; 1 + ncle + nsws
			       c-symbol-key)
			"\\)"
			(concat "\\("	; 2 + ncle + nsws + c-sym-key
				;; Macro with arguments - a "function".
				"\\((\\)" ; 3 + ncle + nsws + c-sym-key
				"\\|"
				;; Macro without arguments - a "variable".
				"\\([^(]\\|$\\)"
				"\\)"))
		       `((if (match-beginning
			      ,(+ 3 ncle-depth nsws-depth
				  (c-lang-const c-symbol-key-depth)))

			     ;; "Function".  Fontify the name and the arguments.
			     (save-restriction
			       (c-put-font-lock-face
				(match-beginning ,(+ 1 ncle-depth nsws-depth))
				(match-end ,(+ 1 ncle-depth nsws-depth))
				'font-lock-function-name-face)
			       (goto-char
				(match-end
				 ,(+ 3 ncle-depth nsws-depth
				     (c-lang-const c-symbol-key-depth))))

			       (narrow-to-region (point-min) limit)
			       (while (and
				       (progn
					 (c-forward-syntactic-ws)
					 (looking-at c-symbol-key))
				       (progn
					 (c-put-font-lock-face
					  (match-beginning 0) (match-end 0)
					  'font-lock-variable-name-face)
					 (goto-char (match-end 0))
					 (c-forward-syntactic-ws)
					 (eq (char-after) ?,)))
				 (forward-char)))

			   ;; "Variable".
			   (c-put-font-lock-face
			    (match-beginning ,(+ 1 ncle-depth nsws-depth))
			    (match-end ,(+ 1 ncle-depth nsws-depth))
			    'font-lock-variable-name-face)))))))

	      ;; Fontify cpp function names in preprocessor
	      ;; expressions in #if and #elif.
	      ,@(when (and (c-lang-const c-cpp-expr-directives)
			   (c-lang-const c-cpp-expr-functions))
		  (let ((ced-re (c-make-keywords-re t
				  (c-lang-const c-cpp-expr-directives)))
			(cef-re (c-make-keywords-re t
				  (c-lang-const c-cpp-expr-functions))))

		    `((,(c-make-font-lock-context-search-function
			 `(,(concat noncontinued-line-end
				    (c-lang-const c-opt-cpp-prefix)
				    ced-re ; 1 + ncle-depth
				    ;; Match the whole logical line to look
				    ;; for the functions in.
				    "\\(\\\\\\(.\\|[\n\r]\\)\\|[^\n\r]\\)*")
			   ((let ((limit (match-end 0)))
			      (while (re-search-forward ,cef-re limit 'move)
				(c-put-font-lock-face (match-beginning 1)
						      (match-end 1)
						      c-preprocessor-face-name)))
			    (goto-char (match-end ,(1+ ncle-depth)))))
			 `(in-cpp-expr
			   (save-excursion (c-end-of-macro) (point))
			   ,cef-re
			   (1 c-preprocessor-face-name t)))))))

	      ;; Fontify the directive names.
	      (,(c-make-font-lock-search-function
		 (concat noncontinued-line-end
			 "\\("
			 (c-lang-const c-opt-cpp-prefix)
			 "[" (c-lang-const c-symbol-chars) "]+"
			 "\\)")
		 `(,(1+ ncle-depth) c-preprocessor-face-name t)))

	      (eval . (list ,(c-make-syntactic-matcher
			      (concat noncontinued-line-end
				      (c-lang-const c-opt-cpp-prefix)
				      "if\\(n\\)def\\_>"))
			    ,(+ ncle-depth 1)
			    c-negation-char-face-name
			    'append))
	      )))

      ,@(when (c-major-mode-is 'pike-mode)
	  ;; Recognize hashbangs in Pike.
	  '((eval . (list "\\`#![^\n\r]*"
			  0 c-preprocessor-face-name))))

      ;; Make hard spaces visible through an inverted `font-lock-warning-face'.
      (eval . (list
	       "\240"
	       0 (progn
		   (unless (c-face-name-p 'c-nonbreakable-space-face)
		     (c-make-inverse-face 'font-lock-warning-face
					  'c-nonbreakable-space-face))
		   ''c-nonbreakable-space-face)))
      ))

(defun c-font-lock-invalid-single-quotes (limit)
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  ;;
  ;; This function fontifies invalid single quotes with
  ;; `font-lock-warning-face'.  These are the single quotes which
  ;; o - aren't inside a literal;
  ;; o - are marked with a syntax-table text property value '(1); and
  ;; o - are NOT marked with a non-null c-digit-separator property.
  (let ((limits (c-literal-limits))
	state beg end)
    (if limits
	(goto-char (cdr limits)))	; Even for being in a ' '
    (while (< (point) limit)
      (setq beg (point))
      (setq state (parse-partial-sexp (point) limit nil nil nil 'syntax-table))
      (setq end (point))
      (goto-char beg)
      (while (progn (skip-chars-forward "^'" end)
		    (< (point) end))
	(if (and (equal (c-get-char-property (point) 'syntax-table) '(1))
		 (not (c-get-char-property (point) 'c-digit-separator)))
	    (c-put-font-lock-face (point) (1+ (point)) 'font-lock-warning-face))
	(forward-char))
      (parse-partial-sexp end limit nil nil state 'syntax-table)))
    nil)

(defun c-maybe-font-lock-wrong-style-comments (limit)
  ;; This function will be called from font-lock-for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  ;;
  ;; This function fontifies "invalid" comment delimiters with
  ;; `font-lock-warning-face'.  A delimiter is "invalid" when
  ;; `c-mark-wrong-style-of-comment' is non-nil, and the delimiter style is
  ;; not the default specified by `c-block-comment-flag'.
  (when c-mark-wrong-style-of-comment
    (let* ((lit (c-semi-pp-to-literal (point)))
	   (s (car lit))		; parse-partial-sexp state.
	   )
      ;; First, deal with and move out of any literal we start in.
      (cond
       ((null (cadr lit)))		; Not in a literal
       ((eq (cadr lit) 'string)
	(setq s (parse-partial-sexp (point) limit nil nil s 'syntax-table)))
       ((and (not c-block-comment-flag) ; In an "invalid" block comment
	     (eq (cadr lit) 'c))
	(setq s (parse-partial-sexp (point) limit nil nil s 'syntax-table))
	;; Font lock the block comment ender with warning face.
	(when (not (nth 4 s))
	  (c-put-font-lock-face (- (point) (length c-block-comment-ender))
				(point) 'font-lock-warning-face)))
       (t ; In a line comment, or a "valid" block comment
	(setq s (parse-partial-sexp (point) limit nil nil s 'syntax-table))))

      (while (< (point) limit)
	(setq s (parse-partial-sexp (point) limit nil nil s 'syntax-table))
	(cond
	 ((or (nth 3 s)			; In a string
	      (and (nth 4 s)		; In a comment
		   (eq (nth 7 s)	; Comment style
		       (if c-block-comment-flag
			   nil		; Block comment
			 1))))	; Line comment
	    ;; Move over a "valid" literal.
	  (setq s (parse-partial-sexp (point) limit nil nil s 'syntax-table)))
	 ((nth 4 s)			; In an invalid comment
	 ;; Fontify the invalid comment opener.
	  (c-put-font-lock-face (nth 8 s) (point) 'font-lock-warning-face)
	  ;; Move to end of comment or LIMIT.
	  (setq s (parse-partial-sexp (point) limit nil nil s 'syntax-table))
	  ;; Fontify an invalid block comment ender, if that's what we have.
	  (when (and (not c-block-comment-flag)
		     (not (nth 4 s)))	; We're outside the comment
	    (c-put-font-lock-face (- (point) (length c-block-comment-ender))
				  (point) 'font-lock-warning-face)))))))
  nil)

(c-lang-defconst c-basic-matchers-before
  "Font lock matchers for basic keywords, labels, references and various
other easily recognizable things that should be fontified before generic
casts and declarations are fontified.  Used on level 2 and higher."

  ;; Note: `c-font-lock-declarations' assumes that no matcher here
  ;; sets `font-lock-type-face' in languages where
  ;; `c-recognize-<>-arglists' is set.

  t `(;; Put a warning face on the opener of unclosed strings that
      ;; can't span lines and on the "terminating" newlines.  Later font
      ;; lock packages have a `font-lock-syntactic-face-function' for
      ;; this, but it doesn't give the control we want since any
      ;; fontification done inside the function will be
      ;; unconditionally overridden.
      ("\\s|" 0 font-lock-warning-face t nil)

      ;; Invalid single quotes.
      c-font-lock-invalid-single-quotes

      ;; Fontify multiline strings.
      ,@(when (c-lang-const c-ml-string-opener-re)
	  '(c-font-lock-ml-strings))

      ;; Fontify keyword constants.
      ,@(when (c-lang-const c-constant-kwds)
	  (let ((re (c-make-keywords-re nil (c-lang-const c-constant-kwds))))
	    (if (c-major-mode-is 'pike-mode)
		;; No symbol is a keyword after "->" in Pike.
		`((eval . (list ,(concat "\\(\\=.?\\|[^>]\\|[^-]>\\)"
					 "\\_<\\(" re "\\)\\_>")
				2 c-constant-face-name)))
	      `((eval . (list ,(concat "\\_<\\(" re "\\)\\_>")
			      1 c-constant-face-name))))))

      ;; Fontify all keywords except the primitive types.
      ,(if (c-major-mode-is 'pike-mode)
	   ;; No symbol is a keyword after "->" in Pike.
	   `(,(concat "\\(\\=.?\\|[^>]\\|[^-]>\\)"
		      "\\_<" (c-lang-const c-regular-keywords-regexp))
	     2 font-lock-keyword-face)
	 `(,(concat "\\_<" (c-lang-const c-regular-keywords-regexp))
	   1 font-lock-keyword-face))

      ;; Fontify leading identifiers in fully qualified names like
      ;; "foo::bar" in languages that supports such things.
      ,@(when (c-lang-const c-opt-identifier-concat-key)
	  (if (c-major-mode-is 'java-mode)
	      ;; Java needs special treatment since "." is used both to
	      ;; qualify names and in normal indexing.  Here we look for
	      ;; capital characters at the beginning of an identifier to
	      ;; recognize the class.  "*" is also recognized to cover
	      ;; wildcard import declarations.  All preceding dot separated
	      ;; identifiers are taken as package names and therefore
	      ;; fontified as references.
	      `(,(c-make-font-lock-search-function
		  ;; Search for class identifiers preceded by ".".  The
		  ;; anchored matcher takes it from there.
		  (concat (c-lang-const c-opt-identifier-concat-key)
			  (c-lang-const c-simple-ws) "*"
			  (concat "\\("
				  "[" c-upper "]"
				  "[" (c-lang-const c-symbol-chars) "]*"
				  "\\|"
				  "\\*"
				  "\\)"))
		  `((let (id-end)
		      (goto-char (1+ (match-beginning 0)))
		      (while (and (eq (char-before) ?.)
				  (progn
				    (backward-char)
				    (c-backward-syntactic-ws)
				    (setq id-end (point))
				    (< (skip-chars-backward
					,(c-lang-const c-symbol-chars))
				       0))
				  (not (get-text-property (point) 'face)))
			(c-put-font-lock-face (point) id-end
					      c-reference-face-name)
			(c-backward-syntactic-ws)))
		    nil
		    (goto-char (match-end 0)))))

	    `((,(byte-compile
		 ;; Must use a function here since we match longer than
		 ;; we want to move before doing a new search.  This is
		 ;; not necessary for XEmacs since it restarts the
		 ;; search from the end of the first highlighted
		 ;; submatch (something that causes problems in other
		 ;; places).
		 `(lambda (limit)
		    (while (re-search-forward
			    ,(concat "\\(\\_<"
				     "\\(" (c-lang-const c-symbol-key) "\\)" ; 2
				     (c-lang-const c-simple-ws) "*"
				     (c-lang-const c-opt-identifier-concat-key)
				     (c-lang-const c-simple-ws) "*"
				     "\\)"
				     "\\("
				     (c-lang-const c-opt-after-id-concat-key)
				     "\\)")
			    limit t)
		      (unless (progn
				(goto-char (match-beginning 0))
				(c-skip-comments-and-strings limit))
			(or (get-text-property (match-beginning 2) 'face)
			    (c-put-font-lock-face (match-beginning 2)
						  (match-end 2)
						  c-reference-face-name))
			(goto-char (match-end 1))))))))))

      ;; Module declarations (e.g. in C++20).
      ,@(when (c-major-mode-is 'c++-mode)
	  '(c-font-lock-c++-modules))

      ,@(when (c-lang-const c-equals-nontype-decl-kwds)
	  `((,(concat (c-lang-const c-equals-nontype-decl-key)
		      (c-lang-const c-simple-ws) "+\\("
		      (c-lang-const c-symbol-key) "\\)")
	     (,(+ 1 (regexp-opt-depth
		     (c-lang-const c-equals-nontype-decl-key))
		  (c-lang-const c-simple-ws-depth))
	      font-lock-type-face t))))

      ;; Fontify the special declarations in Objective-C.
      ,@(when (c-major-mode-is 'objc-mode)
	  `(;; Fontify class names in the beginning of message expressions.
	    ,(c-make-font-lock-search-function
	      "\\["
	      '((c-fontify-types-and-refs ()
		  (c-forward-syntactic-ws limit)
		  (let ((start (point)))
		    ;; In this case we accept both primitive and known types.
		    (when (eq (c-forward-type) 'known)
		      (goto-char start)
		      (let ((c-promote-possible-types t))
			(c-forward-type))))
		  (if (> (point) limit) (goto-char limit)))))

	    ;; The @interface/@implementation/@protocol directives.
	    ,(c-make-font-lock-search-function
	      (regexp-opt
	       '("@interface" "@implementation" "@protocol")
	       'symbols)
	      '((c-fontify-types-and-refs
		    (;; The font-lock package in Emacs is known to clobber
		     ;; `parse-sexp-lookup-properties' (when it exists).
		     (parse-sexp-lookup-properties
		      (cc-eval-when-compile
			(boundp 'parse-sexp-lookup-properties))))
		  (c-forward-objc-directive)
		  nil)
		(goto-char (match-beginning 0))))))

      (eval . (list "\\(!\\)[^=]" 1 c-negation-char-face-name))
      ))

(defun c-font-lock-complex-decl-prepare (limit)
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  ;;
  ;; Called before any of the matchers in `c-complex-decl-matchers'.
  ;;
  ;; This function does hidden buffer changes.

  ;;(message "c-font-lock-complex-decl-prepare %s %s" (point) limit)
  (c-skip-comments-and-strings limit)
  (when (< (point) limit)

    ;; Clear the c-type char properties which mark the region, to recalculate
    ;; them properly.  The most interesting properties are those put on the
    ;; closest token before the region.
    (save-excursion
      (let ((pos (point)))
	(c-backward-syntactic-ws (max (- (point) 500) (point-min)))
	(when (and (not (bobp))
		   (memq (c-get-char-property (1- (point)) 'c-type)
			 '(c-decl-arg-start
			   c-decl-end
			   c-decl-id-start
			   c-decl-type-start
			   c-not-decl)))
	  (setq pos (1- (point))))
	(c-clear-char-properties pos limit 'c-type)
	(c-clear-char-properties pos limit 'c-<>-c-types-set)))

    ;; Update `c-state-cache' to the beginning of the region.  This will
    ;; make `c-beginning-of-syntax' go faster when it's used later on,
    ;; and it's near the point most of the time.
    (c-parse-state)

    ;; Check if the fontified region starts inside a declarator list so
    ;; that `c-font-lock-declarators' should be called at the start.
    ;; The declared identifiers are font-locked correctly as types, if
    ;; that is what they are.
    (let ((prop (save-excursion
		  (c-backward-syntactic-ws (max (- (point) 500) (point-min)))
		  (unless (bobp)
		    (c-get-char-property (1- (point)) 'c-type)))))
      (when (memq prop '(c-decl-id-start c-decl-type-start))
	(c-forward-syntactic-ws limit)
	(c-font-lock-declarators limit t (eq prop 'c-decl-type-start)
				 (not (c-bs-at-toplevel-p (point))))))

    (setq c-font-lock-context ;; (c-guess-font-lock-context)
	  (save-excursion
	    (if (and c-cpp-expr-intro-re
		     (c-beginning-of-macro)
		     (looking-at c-cpp-expr-intro-re))
		'in-cpp-expr)))
    nil))

(defun c-font-lock-<>-arglists (limit)
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  ;;
  ;; Fontify types and references in names containing angle bracket
  ;; arglists from the point to LIMIT.  Note that
  ;; `c-font-lock-declarations' has already handled many of them.
  ;;
  ;; This function might do hidden buffer changes.

  (c-skip-comments-and-strings limit)
  (when (< (point) limit)

    (let (;; The font-lock package in Emacs is known to clobber
	  ;; `parse-sexp-lookup-properties' (when it exists).
	  (parse-sexp-lookup-properties
	   (cc-eval-when-compile
	     (boundp 'parse-sexp-lookup-properties)))
	  (c-parse-and-markup-<>-arglists t)
	  c-restricted-<>-arglists
	  id-start id-end id-face pos kwd-sym
	  old-pos)

      (while (and (< (point) limit)
		  (setq old-pos (point))
		  (c-syntactic-re-search-forward "<" limit t nil t))
	(setq pos (point))
	(save-excursion
	  (backward-char)
	  (c-backward-syntactic-ws old-pos)
	  (if (re-search-backward
	       (concat "\\(\\`\\|" c-nonsymbol-key "\\)\\(" c-symbol-key"\\)\\=")
	       old-pos t)
	      (setq id-start (match-beginning 2)
		    id-end (match-end 2))
	    (setq id-start nil id-end nil)))

	(when id-start
	  (goto-char id-start)
	  (unless (c-skip-comments-and-strings limit)
	    (setq kwd-sym nil
		  c-restricted-<>-arglists nil
		  id-face (get-text-property id-start 'face))

	    (if (cond
		 ((eq id-face 'font-lock-type-face)
		  ;; The identifier got the type face so it has already been
		  ;; handled in `c-font-lock-declarations'.
		  nil)

		 ((eq id-face 'font-lock-keyword-face)
		  (when (looking-at c-opt-<>-sexp-key)
		    ;; There's a special keyword before the "<" that tells
		    ;; that it's an angle bracket arglist.
		    (setq kwd-sym (c-keyword-sym (match-string 2)))))

		 (t
		  ;; There's a normal identifier before the "<".  If we're not in
		  ;; a declaration context then we set `c-restricted-<>-arglists'
		  ;; to avoid recognizing templates in function calls like "foo (a
		  ;; < b, c > d)".
		  (c-backward-syntactic-ws)
		  (when (and (memq (char-before) '(?\( ?,))
			     (not (eq (get-text-property (1- (point)) 'c-type)
				      'c-decl-arg-start)))
		    (setq c-restricted-<>-arglists t))
		  t))

		(progn
		  (goto-char (1- pos))
		  ;; Check for comment/string both at the identifier and
		  ;; at the "<".
		  (unless (c-skip-comments-and-strings limit)

		    (c-fontify-types-and-refs ()
		      (when (c-forward-<>-arglist (c-keyword-member
						   kwd-sym 'c-<>-type-kwds))
			(when (and c-opt-identifier-concat-key
				   (not (get-text-property id-start 'face)))
			  (c-forward-syntactic-ws)
			  (cond ((looking-at c-opt-identifier-concat-key)
				 (c-put-font-lock-face id-start id-end
						       c-reference-face-name))
				((eq (char-after) ?\())
				(t (c-put-font-lock-face id-start id-end
							 'font-lock-type-face))))))

		    (goto-char pos)))
	      (goto-char pos)))))))
  nil)

(defun c-font-lock-declarators (limit list types not-top
				      &optional template-class accept-anon)
  ;; Assuming the point is at the start of a declarator in a declaration,
  ;; fontify the identifier it declares.  (If TYPES is t, it does this via the
  ;; macro `c-fontify-types-and-refs'.)
  ;;
  ;; If LIST is non-nil, also fontify the ids in any following declarators in
  ;; a comma separated list (e.g.  "foo" and "*bar" in "int foo = 17, *bar;");
  ;; additionally, mark the commas with c-type property 'c-decl-id-start or
  ;; 'c-decl-type-start (according to TYPES).  Stop at LIMIT.
  ;;
  ;; If TYPES is t, fontify all identifiers as types; if it is a number, a
  ;; buffer position, additionally set the `c-typedef' text property on the
  ;; keyword at that position; if it is nil fontify as either variables or
  ;; functions, otherwise TYPES is a face to use.  If NOT-TOP is non-nil, we
  ;; are not at the top-level ("top-level" includes being directly inside a
  ;; class or namespace, etc.).
  ;;
  ;; TEMPLATE-CLASS is non-nil when the declaration is in template delimiters
  ;; and was introduced by, e.g. "typename" or "class", such that if there is
  ;; a default (introduced by "="), it will be fontified as a type.
  ;; E.g. "<class X = Y>".
  ;;
  ;; ACCEPT-ANON is non-nil when we accept anonymous declarators.
  ;;
  ;; Nil is always returned.  The function leaves point at the delimiter after
  ;; the last declarator it processes.
  ;;
  ;; This function might do hidden buffer changes.

  ;;(message "c-font-lock-declarators from %s to %s" (point) limit)
  (c-fontify-types-and-refs
      ()
    ;; If we're altering the declarators in a typedef, we need to scan ALL of
    ;; them because of the way we check for changes.
    (let ((c-do-decl-limit (if (numberp types) (point-max) limit))
	  decl-ids)
    (c-do-declarators
     c-do-decl-limit
     list not-top
     (cond ((or (numberp types)
		(eq types t))
	    'c-decl-type-start)
	   ((null types) 'c-decl-id-start))
     (lambda (id-start id-end end-pos _not-top is-function init-char)
       (if (or (numberp types)
	       (eq types t))
	   (when id-start
	     ;; Register and fontify the identifier as a type.
	     (let ((c-promote-possible-types t))
	       (goto-char id-start)
	       (c-forward-type))
	     (when (numberp types)
	       (push (buffer-substring-no-properties id-start id-end)
		     decl-ids)))
	 (when id-start
	   (goto-char id-start)
	   (when c-opt-identifier-prefix-key
	     (unless (and (looking-at c-opt-identifier-prefix-key) ; For operator~
			  (eq (match-end 1) id-end))
	       (while (and (< (point) id-end)
			   (re-search-forward c-opt-identifier-prefix-key id-end t))
		 (c-forward-syntactic-ws c-do-decl-limit))))
	   ;; Only apply the face when the text doesn't have one yet.
	   ;; Exception: The "" in C++'s operator"" will already wrongly have
	   ;; string face.
	   (when (memq (get-text-property (point) 'face)
		       '(nil font-lock-string-face))
	     (c-put-font-lock-face (point) id-end
				   (cond
				    ((not (memq types '(nil t))) types)
				    (is-function 'font-lock-function-name-face)
				    (t 'font-lock-variable-name-face))))
	   ;; Fontify any _tag in C++'s operator"" _tag.
	   (when (and
		  (c-major-mode-is 'c++-mode)
		  (equal (buffer-substring-no-properties id-start id-end)
			 "\"\""))
	     (goto-char id-end)
	     (c-forward-syntactic-ws c-do-decl-limit)
	     (when (c-on-identifier)
	       (c-put-font-lock-face
		(point)
		(progn (c-forward-over-token) (point))
		'font-lock-function-name-face)))))
       (and template-class
	    (eq init-char ?=)		; C++ "<class X = Y>"?
	    (progn
	      (goto-char end-pos)
	      (c-forward-token-2 1 nil c-do-decl-limit) ; Over "="
	      (let ((c-promote-possible-types t))
		(c-forward-type t)))))
     accept-anon)			; Last argument to c-do-declarators.
    ;; If we've changed types declared by a "typedef", update the `c-typedef'
    ;; text property.
    (when (numberp types)
      (let* ((old-decl-ids (c-get-char-property types 'c-typedef))
	     (old-types (c--set-difference old-decl-ids decl-ids :test #'equal))
	     (new-types (c--set-difference decl-ids old-decl-ids :test #'equal)))
	(dolist (type old-types)
	  (c-unfind-type type))
	;; The new types have already been added to `c-found-types', as needed.
	(when (or old-types new-types)
	  (c-put-char-property types 'c-typedef decl-ids)))))
    nil))

(defun c-get-fontification-context (match-pos not-front-decl &optional toplev)
  ;; Return a cons (CONTEXT . RESTRICTED-<>-ARGLISTS) for MATCH-POS.
  ;; NOT-FRONT-DECL is non-nil when a declaration later in the buffer than
  ;; MATCH-POS has already been parsed.  TOPLEV is non-nil when MATCH-POS is
  ;; known to be at "top level", i.e. outside any braces, or directly inside a
  ;; namespace, class, etc.
  ;;
  ;; CONTEXT is the fontification context of MATCH-POS, and is one of the
  ;; following:
  ;; 'decl     In a comma-separated declaration context (typically
  ;;           inside a function declaration arglist).
  ;; '<>       In an angle bracket arglist.
  ;; 'arglist  Some other type of arglist.
  ;; 'generic  In a C11 _Generic construct.
  ;; 'top      Some other context and point is at the top-level (either
  ;;           outside any braces or directly inside a class or namespace,
  ;;           etc.)
  ;; nil       Some other context or unknown context.  Includes
  ;;           within the parens of an if, for, ... construct.
  ;; 'not-decl Definitely not in a declaration.
  ;;
  ;; RESTRICTED-<>-ARGLISTS is non-nil when a scan of template/generic
  ;; arguments lists (i.e. lists enclosed by <...>) is more strict about what
  ;; characters it allows within the list.
  (let ((type (and (> match-pos (point-min))
		   (c-get-char-property (1- match-pos) 'c-type)))
	id-pos tok-end-pos)
    (cond
     ;; Are we just after something like "(foo((bar))" ?
     ((and (eq (char-before match-pos) ?\))
	   (c-go-list-backward match-pos)
	   (progn
	     (c-backward-syntactic-ws)
	     (setq tok-end-pos (point))
	     (cond
	      ((and (setq id-pos (c-on-identifier))
		    (goto-char id-pos)
		    (progn
		      (c-backward-syntactic-ws)
		      (eq (char-before) ?\()))
	       (c-get-fontification-context (point) not-front-decl toplev))
	      ((progn
		 (goto-char tok-end-pos)
		 (and (zerop (c-backward-token-2))
		      (looking-at c-type-internal-paren-key)))
	       (cons 'not-decl nil))))))
     ((not (memq (char-before match-pos) '(?\( ?, ?\[ ?< ?{)))
      (cons (and toplev 'top) nil))
     ;; A control flow expression or a decltype, etc.
     ((and (eq (char-before match-pos) ?\()
	   (save-excursion
	     (goto-char match-pos)
	     (backward-char)
	     (c-backward-token-2)
	     (cond
	      ((looking-at c-paren-stmt-key)
	       ;; Allow comma separated <> arglists in for statements.
	       (cons nil nil))
	      ((or (looking-at c-block-stmt-2-key)
		   (looking-at c-block-stmt-1-2-key)
		   (looking-at c-typeof-key)
		   (looking-at c-type-internal-paren-key))
	       (cons nil t))
	      (t nil)))))
     ;; Near BOB.
     ((<= match-pos (point-min))
      (cons 'arglist t))
     ;; Got a cached hit in a declaration arglist.
     ((eq type 'c-decl-arg-start)
      (cons 'decl nil))
     ;; We're inside (probably) a brace list.
     ((eq type 'c-not-decl)
      (cons 'not-decl nil))
     ;; Inside a C++11 lambda function arglist.
     ((and (c-major-mode-is 'c++-mode)
	   (eq (char-before match-pos) ?\()
	   (save-excursion
	     (goto-char match-pos)
	     (c-backward-token-2)
	     (and
	      (c-safe (goto-char (scan-sexps (point) -1)))
	      (c-looking-at-c++-lambda-capture-list))))
      (c-put-char-property (1- match-pos) 'c-type
			   'c-decl-arg-start)
      (cons 'decl nil))
     ;; We're inside a brace list/enum list.
     ((and (eq (char-before match-pos) ?{)
	   (or (c-at-enum-brace (1- match-pos))
	       (c-at-bracelist-p (1- match-pos)
				 (cdr (c-parse-state)))))
      (c-put-char-property (1- match-pos) 'c-type
			   'c-not-decl)
      (cons 'not-decl nil))
     ;; We're inside an "ordinary" open brace.
     ((eq (char-before match-pos) ?{)
      (cons (and toplev 'top) nil))
     ;; Inside an angle bracket arglist.
     ((or (eq type 'c-<>-arg-sep)
	  (eq (char-before match-pos) ?<))
      (cons '<> nil))
     ;; Got a cached hit in some other type of arglist.
     (type
      (cons 'arglist t))
     ;; We're at a C++ uniform initialization.
     ((and (c-major-mode-is 'c++-mode)
	   (eq (char-before match-pos) ?\()
	   (save-excursion
	     (goto-char match-pos)
	     (and
	      (zerop (c-backward-token-2 2))
	      (looking-at c-identifier-start)
	      (c-got-face-at (point)
			     '(font-lock-variable-name-face)))))
      (cons 'not-decl nil))
     ((and not-front-decl
	   ;; The point is within the range of a previously
	   ;; encountered type decl expression, so the arglist
	   ;; is probably one that contains declarations.
	   ;; However, if `c-recognize-paren-inits' is set it
	   ;; might also be an initializer arglist.
	   (or (not c-recognize-paren-inits)
	       (save-excursion
		 (goto-char match-pos)
		 (not (c-back-over-member-initializers)))))
      ;; The result of this check is cached with a char
      ;; property on the match token, so that we can look
      ;; it up again when refontifying single lines in a
      ;; multiline declaration.
      (c-put-char-property (1- match-pos)
			   'c-type 'c-decl-arg-start)
      (cons 'decl nil))
     ;; Got (an) open paren(s) preceded by an arith operator.
     ((and (eq (char-before match-pos) ?\()
	   (save-excursion
	     (goto-char match-pos)
	     (while
		 (and (zerop (c-backward-token-2))
		      (eq (char-after) ?\()))
	     (looking-at c-arithmetic-op-regexp)))
      (cons nil nil))
     ;; In a C++ member initialization list.
     ((and (eq (char-before match-pos) ?,)
	   (c-major-mode-is 'c++-mode)
	   (save-excursion
	     (goto-char match-pos)
	     (c-back-over-member-initializers)))
      (c-put-char-property (1- match-pos) 'c-type 'c-not-decl)
      (cons 'not-decl nil))
     ;; In a C11 _Generic construct.
     ((and c-generic-key
	   (eq (char-before match-pos) ?,)
	   (save-excursion
	     (and (c-go-up-list-backward match-pos
					 (max (- (point) 2000) (point-min)))
		  (zerop (c-backward-token-2))
		  (looking-at c-generic-key))))
      (cons 'generic nil))
     ;; At start of a declaration inside a declaration paren.
     ((save-excursion
	(goto-char match-pos)
	(and (memq (char-before match-pos) '(?\( ?\,))
	     (c-go-up-list-backward match-pos
					; c-determine-limit is too slow, here.
				    (max (- (point) 2000) (point-min)))
	     (eq (char-after) ?\()
	     (let ((type (c-get-char-property (point) 'c-type)))
	       (or (memq type '(c-decl-arg-start c-decl-type-start))
		   (progn
		     (c-backward-syntactic-ws)
		     (cond
		      ((and toplev
			    (eq (char-before) ?\)))
		       (save-excursion
			 (and (c-go-list-backward nil (max (- (point) 2000)
							   (point-min)))
			      (eq (char-after) ?\()
			      (progn (c-backward-syntactic-ws)
				     (c-back-over-compound-identifier)))))
		      ((save-excursion
			 (and
			  (c-back-over-compound-identifier)
			  (progn
			    (c-backward-syntactic-ws)
			    (or (bobp)
				(progn
				  (setq type (c-get-char-property (1- (point))
								  'c-type))
				  (memq type '(c-decl-arg-start
					       c-decl-type-start))))))))
		      ((and (zerop (c-backward-token-2))
			    (looking-at c-fun-name-substitute-key)))))))))
      ;; Cache the result of this test for next time around.
      (c-put-char-property (1- match-pos) 'c-type 'c-decl-arg-start)
      (cons 'decl nil))
     (t (cons 'arglist t)))))

(defun c-font-lock-single-decl (limit decl-or-cast match-pos context toplev)
  ;; Try to fontify a single declaration, together with all its declarators.
  ;; Return nil if we're successful, non-nil if we fail.  POINT should be
  ;; positioned at the start of the putative declaration before calling.
  ;; POINT is left undefined by this function.
  ;;
  ;; LIMIT sets a maximum position we'll fontify out to.
  ;; DECL-OR-CAST has the form of a result from `c-forward-decl-or-cast-1',
  ;;   and must indicate a declaration (i.e. not be nil or 'cast).
  ;; MATCH-POS is the position after the last symbol before the decl.
  ;; CONTEXT is the context of the current decl., as determined by
  ;;   c-get-fontification-context.
  ;; TOPLEV is non-nil if the decl. is at the top level (i.e. outside any
  ;;   braces, or directly inside a class, namespace, etc.)

  ;; Do we have an expression as the second or third clause of
  ;; a "for" paren expression?
  (if (save-excursion
	(and
	 (car (cddr decl-or-cast))	; maybe-expression flag.
	 (c-go-up-list-backward nil (c-determine-limit 500))
	 (eq (char-after) ?\()
	 (progn (c-backward-syntactic-ws)
		(c-simple-skip-symbol-backward))
	 (looking-at c-paren-stmt-key)
	 (progn (goto-char match-pos)
		(while (and (eq (char-before) ?\))
			    (c-go-list-backward))
		  (c-backward-syntactic-ws))
		(eq (char-before) ?\;))))
      ;; We've got an expression in "for" parens.  Remove the
      ;; "type" that would spuriously get fontified.
      (let ((elt (and (consp c-record-type-identifiers)
		      (assq (cadr (cddr decl-or-cast))
			    c-record-type-identifiers))))
	(when elt
	  (setq c-record-type-identifiers
		(c-delq-from-dotted-list
		 elt c-record-type-identifiers)))
	t)
    ;; Back up to the type to fontify the declarator(s).
    (goto-char (car decl-or-cast))

    (let ((decl-list
	   (if (not (memq context '(nil top)))
	       ;; Should normally not fontify a list of
	       ;; declarators inside an arglist, but the first
	       ;; argument in the ';' separated list of a "for"
	       ;; statement is an exception.
	       (when (eq (char-before match-pos) ?\()
		 (save-excursion
		   (goto-char (1- match-pos))
		   (c-backward-syntactic-ws)
		   (and (c-simple-skip-symbol-backward)
			(looking-at c-paren-stmt-key))))
	     t))
	  (template-class (and (eq context '<>)
			       (save-excursion
				 (goto-char match-pos)
				 (c-forward-syntactic-ws)
				 (looking-at c-template-typename-key)))))
      ;; Fix the `c-decl-id-start' or `c-decl-type-start' property
      ;; before the first declarator if it's a list.
      ;; `c-font-lock-declarators' handles the rest.
      (when decl-list
	(save-excursion
	  (c-backward-syntactic-ws)
	  (unless (bobp)
	    (c-put-char-property (1- (point)) 'c-type
				 (if (cadr decl-or-cast)
				     'c-decl-type-start
				   'c-decl-id-start)))))
      (c-font-lock-declarators
       (min limit (point-max))
       decl-list
       (cond ((null (cadr decl-or-cast))
	      nil)
	     ((cadr (cadr decl-or-cast)))
	     (t t))
       (not toplev)
       template-class
       (memq context '(decl <>))))

    ;; A declaration has been successfully identified, so do all the
    ;; fontification of types and refs that've been recorded.
    (c-fontify-recorded-types-and-refs)
    nil))


(defun c-font-lock-declarations (limit)
  ;; Fontify all the declarations, casts and labels from the point to LIMIT.
  ;; Assumes that strings and comments have been fontified already.
  ;;
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  ;;
  ;; This function might do hidden buffer changes.

  ;;(message "c-font-lock-declarations search from %s to %s" (point) limit)
  (c-skip-comments-and-strings limit)
  (when (< (point) limit)

    (save-restriction
      (let (;; The position where `c-find-decl-spots' last stopped.
	    start-pos
	    ;; o - 'decl if we're in an arglist containing declarations
	    ;;   (but if `c-recognize-paren-inits' is set it might also be
	    ;;   an initializer arglist);
	    ;; o - '<> if the arglist is of angle bracket type;
	    ;; o - 'arglist if it's some other arglist;
	    ;; o - nil, if not in an arglist at all.  This includes the
	    ;;   parenthesized condition which follows "if", "while", etc.
	    context
	    ;; A list of starting positions of possible type declarations, or of
	    ;; the typedef preceding one, if any.
	    last-cast-end
	    ;; The result from `c-forward-decl-or-cast-1'.
	    decl-or-cast
	    ;; The maximum of the end positions of all the checked type
	    ;; decl expressions in the successfully identified
	    ;; declarations.  The position might be either before or
	    ;; after the syntactic whitespace following the last token
	    ;; in the type decl expression.
	    (max-type-decl-end 0)
	    ;; Same as `max-type-decl-*', but used when we're before
	    ;; `token-pos'.
	    (max-type-decl-end-before-token 0)
	    ;; End of <..> construct which has had c-<>-arg-sep c-type
	    ;; properties set within it.
	    (max-<>-end 0)
	    ;; Set according to the context to direct the heuristics for
	    ;; recognizing C++ templates.
	    c-restricted-<>-arglists
	    ;; Turn on recording of identifier ranges in
	    ;; `c-forward-decl-or-cast-1' and `c-forward-label' for
	    ;; later fontification.
	    (c-record-type-identifiers t)
	    label-type
	    c-record-ref-identifiers
	    ;; Make `c-forward-type' calls mark up template arglists if
	    ;; it finds any.  That's necessary so that we later will
	    ;; stop inside them to fontify types there.
	    (c-parse-and-markup-<>-arglists t)
	    ;; The font-lock package in Emacs is known to clobber
	    ;; `parse-sexp-lookup-properties' (when it exists).
	    (parse-sexp-lookup-properties
	     (cc-eval-when-compile
	       (boundp 'parse-sexp-lookup-properties)))
	    list-bounds)

	;; Below we fontify a whole declaration even when it crosses the limit,
	;; to avoid gaps when jit/lazy-lock fontifies the file a block at a
	;; time.  That is however annoying during editing, e.g. the following is
	;; a common situation while the first line is being written:
	;;
	;;     my_variable
	;;     some_other_variable = 0;
	;;
	;; font-lock will put the limit at the beginning of the second line
	;; here, and if we go past it we'll fontify "my_variable" as a type and
	;; "some_other_variable" as an identifier, and the latter will not
	;; correct itself until the second line is changed.  To avoid that we
	;; narrow to the limit if the region to fontify is a single line.
	(if (<= limit (c-point 'bonl))
	    (narrow-to-region
	     (point-min)
	     (save-excursion
	       ;; Narrow after any operator chars following the limit though,
	       ;; since those characters can be useful in recognizing a
	       ;; declaration (in particular the '{' that opens a function body
	       ;; after the header).
	       (goto-char limit)
	       (skip-chars-forward c-nonsymbol-chars)
	       (point))))

	(c-find-decl-spots
	 limit
	 c-decl-start-re
	 (eval c-maybe-decl-faces)

	 (lambda (match-pos inside-macro &optional toplev)
	   ;; Note to maintainers: don't use `limit' inside this lambda form;
	   ;; c-find-decl-spots sometimes narrows to less than `limit'.
	   (setq start-pos (point))
	   (when
	       ;; The result of the form below is true when we don't recognize a
	       ;; declaration or cast, and we don't recognize a "non-decl",
	       ;; typically a brace list.
	       (if (or (and (eq (get-text-property (point) 'face)
				'font-lock-keyword-face)
			    (looking-at c-not-decl-init-keywords))
		       (and c-macro-with-semi-re
			    (looking-at c-macro-with-semi-re))) ; 2008-11-04
		   ;; Don't do anything more if we're looking at a keyword that
		   ;; can't start a declaration.
		   t

		 ;; Set `context' and `c-restricted-<>-arglists'.  Look for
		 ;; "<" for the sake of C++-style template arglists.
		 ;; Ignore "(" when it's part of a control flow construct
		 ;; (e.g. "for (").
		 (let ((got-context
			(c-get-fontification-context
			 match-pos
			 (< match-pos (if inside-macro
					  max-type-decl-end-before-token
					max-type-decl-end))
			 toplev)))
		   (setq context (car got-context)
			 c-restricted-<>-arglists (cdr got-context)))

		 ;; Check we haven't missed a preceding "typedef".
		 (when (not (looking-at c-typedef-key))
		   (c-backward-syntactic-ws
		    (max (- (point) 1000) (point-min)))
		   (c-backward-token-2)
		   (or (looking-at c-typedef-key)
		       (goto-char start-pos)))

		 ;; In QT, "more" is an irritating keyword that expands to nothing.
		 ;; We skip over it to prevent recognition of "more slots: <symbol>"
		 ;; as a bitfield declaration.
		 (when (and (c-major-mode-is 'c++-mode)
			    (looking-at "\\_<\\(more\\)\\_>"))
		   (goto-char (match-end 1))
		   (c-forward-syntactic-ws))

		 ;; Now analyze the construct.
		 (cond
		  ((eq context 'not-decl)
		   (setq decl-or-cast nil)
		   (if (c-syntactic-re-search-forward
			"," (min limit (point-max)) 'at-limit t)
		       (c-put-char-property (1- (point)) 'c-type 'c-not-decl))
		   nil)
		  ((eq context 'generic)
		   (c-font-lock-c11-generic-clause))

		  ;; K&R parameters.
		  ((and
		    c-recognize-knr-p
		    (or toplev inside-macro)
		    (eq context 'decl)
		    (setq list-bounds (c-in-id-arglist))
		    (save-excursion
		      (goto-char (car list-bounds))
		      (and (zerop (c-backward-token-2))
			   (eq (point) (c-on-identifier))))
		    (save-excursion
		      (goto-char (cdr list-bounds))
		      (c-forward-syntactic-ws)
		      (not (memq (char-after) '(?\; ?{ ?\? ?: ?\,)))))
		   ;; Nothing to fontify.
		   (goto-char (cdr list-bounds)))

		  (t
		   (setq decl-or-cast
			 (c-forward-decl-or-cast-1
			  match-pos context last-cast-end inside-macro))

		   ;; Ensure that c-<>-arg-sep c-type properties are in place on the
		   ;; commas separating the arguments inside template/generic <..>s.
		   (when (and (eq (char-before match-pos) ?<)
			      (> match-pos max-<>-end))
		     (save-excursion
		       (goto-char match-pos)
		       (c-backward-token-2)
		       (if (and
			    (eq (char-after) ?<)
			    (let ((c-restricted-<>-arglists
				   (save-excursion
				     (c-backward-token-2)
				     (and
				      (not (looking-at c-opt-<>-sexp-key))
				      (progn
					(c-backward-syntactic-ws
					 (max (- (point) 1000) (point-min)))
					(memq (char-before) '(?\( ?,)))
				      (not (eq (c-get-char-property (1- (point))
								    'c-type)
					       'c-decl-arg-start))))))
			      (c-forward-<>-arglist nil)))
			   (setq max-<>-end (point)))))

		   (cond
		    ((eq decl-or-cast 'cast)
		     ;; Save the position after the previous cast so we can feed
		     ;; it to `c-forward-decl-or-cast-1' in the next round.  That
		     ;; helps it discover cast chains like "(a) (b) c".
		     (setq last-cast-end (point))
		     (c-fontify-recorded-types-and-refs)
		     nil)

		    (decl-or-cast
		     ;; We've found a declaration.

		     ;; Set `max-type-decl-end' or `max-type-decl-end-before-token'
		     ;; under the assumption that we're after the first type decl
		     ;; expression in the declaration now.  That's not really true;
		     ;; we could also be after a parenthesized initializer
		     ;; expression in C++, but this is only used as a last resort
		     ;; to slant ambiguous expression/declarations, and overall
		     ;; it's worth the risk to occasionally fontify an expression
		     ;; as a declaration in an initializer expression compared to
		     ;; getting ambiguous things in normal function prototypes
		     ;; fontified as expressions.
		     (if inside-macro
			 (when (> (point) max-type-decl-end-before-token)
			   (setq max-type-decl-end-before-token (point)))
		       (when (> (point) max-type-decl-end)
			 (setq max-type-decl-end (point))))
		     (goto-char start-pos)
		     (c-font-lock-single-decl limit decl-or-cast match-pos
					      context
					      (or toplev (nth 4 decl-or-cast))))

		    (t t)))))

	     ;; It was a false alarm.  Check if we're in a label (or other
	     ;; construct with `:' except bitfield) instead.
	     (goto-char start-pos)
	     (when (setq label-type (c-forward-label t match-pos nil))
	       ;; Can't use `c-fontify-types-and-refs' here since we
	       ;; use the label face at times.
	       (cond ((eq label-type 'goto-target)
		      (c-put-font-lock-face (caar c-record-ref-identifiers)
					    (cdar c-record-ref-identifiers)
					    c-label-face-name))
		     ((eq label-type 'qt-1kwd-colon)
		      (c-put-font-lock-face (caar c-record-ref-identifiers)
					    (cdar c-record-ref-identifiers)
					    'font-lock-keyword-face))
		     ((eq label-type 'qt-2kwds-colon)
		      (mapc
		       (lambda (kwd)
			 (c-put-font-lock-face (car kwd) (cdr kwd)
					       'font-lock-keyword-face))
		       c-record-ref-identifiers)))
	       (setq c-record-ref-identifiers nil)
	       ;; `c-forward-label' has probably added a `c-decl-end'
	       ;; marker, so return t to `c-find-decl-spots' to signal
	       ;; that.
	       t))))

	nil))))

(defun c-font-lock-c11-generic-clause ()
  ;; Fontify a type inside the C11 _Generic clause.  Point will be at the
  ;; type and will be left at the next comma of the clause (if any) or the
  ;; closing parenthesis, if any, or at the end of the type, otherwise.
  ;; The return value is always nil.
  (c-fontify-types-and-refs
      ((here (point))
       (type-type (c-forward-type t))
       (c-promote-possible-types (if (eq type-type 'maybe) 'just-one t))
       (pos (point)) pos1)
    (when (and type-type (eq (char-after) ?:))
      (goto-char here)
      (c-forward-type t))		; Fontify the type.
    (cond
     ((c-syntactic-re-search-forward "," nil t t t)
      (backward-char))
     ((and (setq pos1 (c-up-list-forward))
	   (eq (char-before pos1) ?\)))
      (goto-char (1- pos1)))
     (t (goto-char pos))))
  nil)

(defun c-font-lock-enum-body (limit)
  ;; Fontify the identifiers of each enum we find by searching forward.
  ;;
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  (while (and (< (point) limit)
	      (search-forward-regexp c-enum-clause-introduction-re limit t))
    (when (c-at-enum-brace (1- (point)))
      (c-forward-syntactic-ws)
      (c-font-lock-declarators limit t nil t)))
  nil)

(defun c-font-lock-enum-tail (limit)
  ;; Fontify an enum's identifiers when POINT is within the enum's brace
  ;; block.
  ;;
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  ;;
  ;; Note that this function won't attempt to fontify beyond the end of the
  ;; current enum block, if any.
  (c-skip-comments-and-strings limit)
  (when (< (point) limit)
    (let* ((paren-state (c-parse-state))
	   (encl-pos (c-most-enclosing-brace paren-state)))
      (when (and
	     encl-pos
	     (eq (char-after encl-pos) ?\{)
	     (c-at-enum-brace encl-pos))
	(c-syntactic-skip-backward "^{," nil t)
	(c-put-char-property (1- (point)) 'c-type 'c-decl-id-start)

	(c-forward-syntactic-ws)
	(c-font-lock-declarators limit t nil t))))
  nil)

(defun c-font-lock-cut-off-declarators (limit)
  ;; Fontify any declarators "cut off" from their declaring type at the start
  ;; of the region being fontified.
  ;;
  ;; This function will be called from font-lock- for a region bounded by
  ;; POINT and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; fontification".
  (c-skip-comments-and-strings limit)
  (when (< (point) limit)
    (let ((here (point))
	  (decl-search-lim (c-determine-limit 1000))
	  paren-state encl-pos token-end context decl-or-cast
	  start-pos top-level c-restricted-<>-arglists
	  c-recognize-knr-p)		; Strictly speaking, bogus, but it
					; speeds up lisp.h tremendously.
      (save-excursion
	(when (not (c-back-over-member-initializers decl-search-lim))
	  (setq paren-state (c-parse-state))
	  (unless (or (eobp)
		      (looking-at "\\s(\\|\\s)"))
	    (forward-char))
	  (c-syntactic-skip-backward "^;{}" decl-search-lim t)
	  ;; Do we have the brace block of a struct, etc.?
	  (when (cond
		 ((and (consp (car paren-state))
		       (eq (char-before) ?}))
		  (goto-char (caar paren-state))
		  t)
		 ((and (numberp (car paren-state))
		       (eq (char-after (car paren-state)) ?{))
		  (goto-char (car paren-state))
		  t))
	    (c-syntactic-skip-backward "^;{}" decl-search-lim t))
	  (when (or (bobp)
		    (memq (char-before) '(?\; ?{ ?})))
	    (setq token-end (point))
	    (c-forward-syntactic-ws here)
	    (when (< (point) here)
	      ;; We're now putatively at the declaration.
	      (setq start-pos (point))
	      (setq paren-state (c-parse-state))
	      ;; At top level or inside a "{"?
	      (if (or (not (setq encl-pos
				 (c-most-enclosing-brace paren-state)))
		      (eq (char-after encl-pos) ?\{))
		  (progn
		    (setq top-level (c-at-toplevel-p))
		    (let ((got-context (c-get-fontification-context
					token-end nil top-level)))
		      (setq context (car got-context)
			    c-restricted-<>-arglists (cdr got-context)))
		    (setq decl-or-cast
			  (c-forward-decl-or-cast-1 token-end context nil))
		    (when (consp decl-or-cast)
		      (goto-char start-pos)
		      (c-font-lock-single-decl limit decl-or-cast token-end
					       context top-level))))))))
      nil)))

(defun c-font-lock-enclosing-decls (limit)
  ;; Fontify the declarators of (nested) declarations we're in the middle of.
  ;; This is mainly for when a jit-lock etc. chunk starts inside the brace
  ;; block of a struct/union/class, etc.
  ;;
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  (c-skip-comments-and-strings limit)
  (when (< (point) limit)
    (let* ((paren-state (c-parse-state))
	   (decl-search-lim (c-determine-limit 1000))
	   in-typedef ps-elt)
      ;; Are we in any nested struct/union/class/etc. braces?
      (while paren-state
	(setq ps-elt (car paren-state)
	      paren-state (cdr paren-state))
	(when (and (atom ps-elt)
		   (eq (char-after ps-elt) ?\{))
	  (goto-char ps-elt)
	  (c-syntactic-skip-backward "^;{}" decl-search-lim)
	  (c-forward-syntactic-ws)
	  (setq in-typedef (looking-at c-typedef-key))
	  (if in-typedef (c-forward-over-token-and-ws))
	  (when (and c-opt-block-decls-with-vars-key
		     (looking-at c-opt-block-decls-with-vars-key))
	    (goto-char ps-elt)
	    (when (c-safe (c-forward-sexp))
	      (c-forward-syntactic-ws)
	      (c-font-lock-declarators limit t in-typedef
				       (not (c-bs-at-toplevel-p (point)))))))))))

(defun c-font-lock-ids-with-dollar (limit)
  ;; Maybe fontify identifiers with a dollar using `font-lock-warning-face'.
  ;; This is done only for languages which tolerate a $ in ids, and only when
  ;; the flag variable `c-warn-ids-with-dollar' is set to non-nil.  This
  ;; function only works after functions such as `c-font-lock-declarations'
  ;; have already been run.
  ;;
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  (when c-warn-ids-with-dollar
    (let (id-start)
      (while (and (< (point) limit)
		  (skip-chars-forward "^$" limit)
		  (< (point) limit)
		  (eq (char-after) ?$))
	(if (and (memq (c-get-char-property (point) 'face)
		       '(font-lock-variable-name-face
			 font-lock-function-name-face
			 font-lock-type-face))
		 (setq id-start (c-on-identifier)))
	    (progn
	      (goto-char id-start)
	      (looking-at c-identifier-key)
	      (c-put-font-lock-face (match-beginning 0) (match-end 0)
				    'font-lock-warning-face)
	      (goto-char (match-end 0)))
	  (forward-char)))
      nil)))

(defun c-font-lock-ml-strings (limit)
  ;; Fontify multi-line strings.
  ;;
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  (let* ((state (c-semi-pp-to-literal (point)))
	 (string-start (and (eq (cadr state) 'string)
			    (car (cddr state))))
	 (open-delim (and string-start
			  (save-excursion
			    (goto-char (1+ string-start))
			    (c-ml-string-opener-around-point))))
	 (string-delims (and open-delim
			     (cons open-delim (c-get-ml-closer open-delim))))
	 found)
    ;; We go round the next loop twice per raw string, once for each "end".
    (while (< (point) limit)
      (cond
       ;; Point is not in an ml string
       ((not string-delims)
	(while (and (setq found (re-search-forward c-ml-string-opener-re
						   limit 'limit))
		    (> (match-beginning 0) (point-min))
		    (memq (c-get-char-property (1- (match-beginning 0)) 'face)
			  '(font-lock-comment-face font-lock-string-face
			    font-lock-comment-delimiter-face))))
	(when found
	  (setq open-delim (cons (match-beginning 1)
				 (cons (match-end 1) (match-beginning 2)))
		string-delims (cons open-delim (c-get-ml-closer open-delim)))
	  (goto-char (caar string-delims))))

       ;; Point is in the body of an ml string.
       ((and string-delims
	     (>= (point) (cadar string-delims))
	     (or (not (cdr string-delims))
		 (< (point) (cadr string-delims))))
	(cond
	 ((cdr string-delims)
	  (goto-char (cadr string-delims)))
	 ((equal (c-get-char-property (1- (cadar string-delims))
				      'syntax-table)
		 '(15))			; "Always" the case.
	  ;; The next search should be successful for an unterminated ml
	  ;; string inside a macro, but not for any other unterminated
	  ;; string.
	  (or (c-search-forward-char-property 'syntax-table '(15) limit)
	      (goto-char limit))
	  (setq string-delims nil))
	 (t (c-benign-error "Messing '(15) syntax-table property at %d"
			    (1- (cadar string-delims)))
	    (setq string-delims nil))))

       ;; Point is at or in a closing delimiter
       ((and string-delims
	     (cdr string-delims)
	     (>= (point) (cadr string-delims)))
	(unless (featurep 'xemacs)
	  (c-put-font-lock-face (cadr string-delims) (1+ (cadr string-delims))
				'font-lock-string-face))
	(c-remove-font-lock-face
	 (if (featurep 'xemacs)
	     (cadr string-delims)
	   (1+ (cadr string-delims)))
	 (caddr string-delims))
	(goto-char (caddr string-delims))
	(setq string-delims nil))

       ;; point is at or in an opening delimiter.
       (t
	(if (cdr string-delims)
	    (progn
	      (c-remove-font-lock-face (caar string-delims)
				       (cadar string-delims))
	      (unless (featurep 'xemacs)
		(c-put-font-lock-face (1- (cadar string-delims))
				      (cadar string-delims)
				      'font-lock-string-face)))
	  (c-put-font-lock-face (caar string-delims) (cadar string-delims)
				'font-lock-warning-face))
	(goto-char (cadar string-delims)))))
    nil))

(defun c-font-lock-c++-lambda-captures (limit)
  ;; Fontify the lambda capture component of C++ lambda declarations.
  ;;
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  (let (mode capture-default id-start id-end declaration sub-begin sub-end tem)
    (while (and (< (point) limit)
		(search-forward "[" limit t))
      (when (progn (backward-char)
		   (prog1
		       (c-looking-at-c++-lambda-capture-list)
		     (forward-char)))
	(c-forward-syntactic-ws)
	(setq mode (and (memq (char-after) '(?= ?&))
			(char-after)))
	;; Is the first element of the list a bare "=" or "&"?
	(when mode
	  (setq tem nil)
	  (save-excursion
	    (forward-char)
	    (c-forward-syntactic-ws)
	    (if (memq (char-after) '(?, ?\]))
		(progn
		  (setq capture-default mode)
		  (when (eq (char-after) ?,)
		    (forward-char)
		    (c-forward-syntactic-ws))
		  (setq tem (point)))))
	  (if tem (goto-char tem)))

	;; Go round the following loop once per captured item.  We use "\\s)"
	;; rather than "\\]" here to avoid infinite looping in this situation:
	;; "unsigned items [] { [ }".  The second "[" triggers this function,
	;; but if we don't match the "}" with an "\\s)", the
	;; `c-syntactic-re-search-forward' at the end of the loop fails to
	;; move forward over it, leaving point stuck at the "}".
	(while (and (not (looking-at "\\s)"))
		    (< (point) limit))
	  (if (eq (char-after) ?&)
	      (progn (setq mode ?&)
		     (forward-char)
		     (c-forward-syntactic-ws))
	    (setq mode ?=))
	  (if (c-on-identifier)
	      (progn
		(setq id-start (point))
		(forward-char)
		(c-end-of-current-token)
		(setq id-end (point))
		(c-forward-syntactic-ws)

		(setq declaration (eq (char-after) ?=))
		(when declaration
		  (forward-char)	; over "="
		  (c-forward-syntactic-ws)
		  (setq sub-begin (point)))
		(if (or (and (< (point) limit)
			     (c-syntactic-re-search-forward "," limit t t))
			(and (c-go-up-list-forward nil limit)
			     (eq (char-before) ?\])))
		    (backward-char)
		  (goto-char limit))
		(when declaration
		  (save-excursion
		    (setq sub-end (point))
		    (goto-char sub-begin)
		    (c-font-lock-c++-lambda-captures sub-end)))

		(c-put-font-lock-face id-start id-end
				      (cond
				       (declaration
					'font-lock-variable-name-face)
				       ((and capture-default
					     (eq mode capture-default))
					'font-lock-warning-face)
				       ((eq mode ?=) 'font-lock-constant-face)
				       (t 'font-lock-variable-name-face))))
	    (c-syntactic-re-search-forward "," limit 'bound t))

	  (c-forward-syntactic-ws)
	  (when (eq (char-after) ?,)
	    (forward-char)
	    (c-forward-syntactic-ws)))

	(setq capture-default nil)
	(if (< (point) limit)
	    (forward-char))))) ; over the terminating "]" or other close paren.
  nil)

(defun c-forward-c++-module-name (limit)
  ;; Is there a C++20 module name at point?  If so, return a cons of the start
  ;; and end of that name, in which case point will be moved over the name and
  ;; following whitespace.  Otherwise nil will be returned and point will be
  ;; unmoved.  This function doesn't regard a partition as part of the name.
  ;; The entire construct must end not after LIMIT.
  (when (and
	 (looking-at c-module-name-re)
	 (<= (match-end 0) limit)
	 (not (looking-at c-keywords-regexp)))
    (goto-char (match-end 0))
    (prog1 (cons (match-beginning 0) (match-end 0))
      (c-forward-syntactic-ws limit))))

(defun c-forward-c++-module-partition-name (limit)
  ;; Is there a C++20 module partition name (starting with its colon) at
  ;; point?  If so return a cons of the start and end of the name, not
  ;; including the colon, in which case point will be move to after the name
  ;; and following whitespace.  Otherwise nil will be returned and point not
  ;; moved.  The entire construct must end not after LIMIT.
  (when (and
	 (eq (char-after) ?:)
	 (progn
	   (forward-char)
	   (c-forward-syntactic-ws limit)
	   (looking-at c-module-name-re))
	 (<= (match-end 0) limit)
	 (not (looking-at c-keywords-regexp)))
    (goto-char (match-end 0))
    (prog1 (cons (match-beginning 0) (match-end 0))
      (c-forward-syntactic-ws limit))))

(defun c-font-lock-c++-modules (limit)
  ;; Fontify the C++20 module stanzas, characterized by the keywords `module',
  ;; `export' and `import'.  Note that this has to be done by a function (as
  ;; opposed to regexps) due to the presence of optional C++ attributes.
  ;;
  ;; This function will be called from font-lock for a region bounded by POINT
  ;; and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; Fontification".
  (while (and (< (point) limit)
	      (re-search-forward "\\_<\\(module\\|export\\|import\\)\\_>"
				 limit t))
    (goto-char (match-end 1))
    (let (name-bounds pos beg end
		      module-names)	; A list of conses of start and end
					; of pertinent module names
      (unless (c-skip-comments-and-strings limit)
	(when
	    (cond
	     ;; module foo...; Note we don't handle module; or module
	     ;; :private; here, since they don't really need handling.
	     ((save-excursion
		(when (equal (match-string-no-properties 1) "export")
		  (c-forward-syntactic-ws limit)
		  (re-search-forward "\\=\\_<\\(module\\)\\_>" limit t))
		(and (equal (match-string-no-properties 1) "module")
		     (< (point) limit)
		     (progn (c-forward-syntactic-ws limit)
			    (setq name-bounds (c-forward-c++-module-name
					       limit)))
		     (setq pos (point))))
	      (push name-bounds module-names)
	      (goto-char pos)
	      ;; Is there a partition name?
	      (when (setq name-bounds (c-forward-c++-module-partition-name
				       limit))
		(push name-bounds module-names))
	      t)

	     ;; import
	     ((save-excursion
		(when (equal (match-string-no-properties 1) "export")
		  (c-forward-syntactic-ws limit)
		  (re-search-forward "\\=\\_<\\(import\\)\\_>" limit t))
		(and (equal (match-string-no-properties 1) "import")
		     (< (point) limit)
		     (progn (c-forward-syntactic-ws limit)
			    (setq pos (point)))))
	      (goto-char pos)
	      (cond
	       ;; import foo;
	       ((setq name-bounds (c-forward-c++-module-name limit))
		(push name-bounds module-names)
		t)
	       ;; import :foo;
	       ((setq name-bounds (c-forward-c++-module-partition-name limit))
		(push name-bounds module-names)
		t)
	       ;; import "foo";
	       ((and (eq (char-after) ?\")
		     (setq pos (point))
		     (c-safe (c-forward-sexp) t)) ; Should already have string face.
		(when (eq (char-before) ?\")
		  (setq beg pos
			end (point)))
		(c-forward-syntactic-ws limit)
		t)
	       ;; import <foo>;
	       ((and (looking-at "<\\(?:\\\\.\\|[^\\\n\r\t>]\\)*\\(>\\)?")
		     (< (match-end 0) limit))
		(setq beg (point))
		(goto-char (match-end 0))
		(when (match-end 1)
		  (setq end (point)))
		(if (featurep 'xemacs)
		    (c-put-font-lock-face
		     (1+ beg) (if end (1- end) (point)) font-lock-string-face)
		  (c-put-font-lock-face
		   beg (or end (point)) 'font-lock-string-face))
		(c-forward-syntactic-ws limit)
		t)
	       (t nil)))

	     ;; export
	     ;; There is no fontification to be done here, but we need to
	     ;; skip over the declaration or declaration sequence.
	     ((save-excursion
		(when (equal (match-string-no-properties 0) "export")
		  (c-forward-syntactic-ws limit)
		  (setq pos (point))))
	      (goto-char (point))
	      (if (eq (char-after) ?{)
		  ;; Declaration sequence.
		  (unless (and (c-go-list-forward nil limit)
			       (eq (char-before) ?}))
		    (goto-char limit)
		    nil)
		;; Single declaration
		(unless (c-end-of-decl-1)
		  (goto-char limit)
		  nil))))		; Nothing more to do, here.

	  ;; Optional attributes?
	  (while (and (c-looking-at-c++-attribute)
		      (< (match-end 0) limit))
	    (goto-char (match-end 0))
	    (c-forward-syntactic-ws limit))
	  ;; Finally, there must be a semicolon.
	  (if (and (< (point) limit)
		   (eq (char-after) ?\;))
	      (progn
		(forward-char)
		;; Fontify any module names we've encountered.
		(dolist (name module-names)
		  (c-put-font-lock-face (car name) (cdr name)
					c-reference-face-name)))
	    ;; No semicolon, so put warning faces on any delimiters.
	    (when beg
	      (c-put-font-lock-face beg (1+ beg) 'font-lock-warning-face))
	    (when end
	      (c-put-font-lock-face (1- end) end 'font-lock-warning-face))))))))

(c-lang-defconst c-simple-decl-matchers
  "Simple font lock matchers for types and declarations.  These are used
on level 2 only and so aren't combined with `c-complex-decl-matchers'."

  t `(;; Objective-C methods.
      ,@(when (c-major-mode-is 'objc-mode)
	  `((,(c-lang-const c-opt-method-key)
	     (,(byte-compile
		(lambda (limit)
		  (let (;; The font-lock package in Emacs is known to clobber
			;; `parse-sexp-lookup-properties' (when it exists).
			(parse-sexp-lookup-properties
			 (cc-eval-when-compile
			   (boundp 'parse-sexp-lookup-properties))))
		    (save-restriction
		      (narrow-to-region (point-min) limit)
		      (c-font-lock-objc-method)))
		  nil))
	      (goto-char (match-end 1))))))

      ;; Fontify all type names and the identifiers in the
      ;; declarations they might start.  Use eval here since
      ;; `c-known-type-key' gets its value from
      ;; `*-font-lock-extra-types' on mode init.
      (eval . (list ,(c-make-font-lock-search-function
		      'c-known-type-key
		      '(1 'font-lock-type-face t)
		      '((c-font-lock-declarators limit t nil nil)
			(save-match-data
			  (goto-char (match-end 1))
			  (c-forward-syntactic-ws))
			(goto-char (match-end 1))))))

      ;; Fontify types preceded by `c-type-prefix-kwds' and the
      ;; identifiers in the declarations they might start.
      ,@(when (c-lang-const c-type-prefix-kwds)
	  (let* ((prefix-re (c-make-keywords-re nil
			      (c-lang-const c-type-prefix-kwds)))
		 (type-match (+ 2
				(regexp-opt-depth prefix-re)
				(c-lang-const c-simple-ws-depth))))
	    `((,(c-make-font-lock-search-function
		 (concat "\\_<\\(" prefix-re "\\)" ; 1
			 (c-lang-const c-simple-ws) "+"
			 (concat "\\("	; 2 + prefix-re + c-simple-ws
				 (c-lang-const c-symbol-key)
				 "\\)"))
		 `(,type-match
		   'font-lock-type-face t)
		 `((c-font-lock-declarators limit t nil nil)
		   (save-match-data
		     (goto-char (match-end ,type-match))
		     (c-forward-syntactic-ws))
		   (goto-char (match-end ,type-match))))))))

      ;; Fontify special declarations that lack a type.
      ,@(when (c-lang-const c-typeless-decl-kwds)
	  `((,(c-make-font-lock-search-function
	       (regexp-opt (c-lang-const c-typeless-decl-kwds) 'symbols)
	       '((c-font-lock-declarators limit t nil nil)
		 (save-match-data
		   (goto-char (match-end 1))
		   (c-forward-syntactic-ws))
		 (goto-char (match-end 1)))))))

      ;; Fontify generic colon labels in languages that support them.
      ,@(when (c-lang-const c-recognize-colon-labels)
	  '(c-font-lock-labels))

      ;; Maybe fontify identifiers containing a dollar sign with
      ;; `font-lock-warning-face'.
      ,@(when (c-lang-const c-dollar-in-ids)
	  `(c-font-lock-ids-with-dollar))))

(c-lang-defconst c-complex-decl-matchers
  "Complex font lock matchers for types and declarations.  Used on level
3 and higher."

  ;; Note: This code in this form dumps a number of functions into the
  ;; resulting constant, `c-matchers-3'.  At run time, font lock will call
  ;; each of them as a "FUNCTION" (see Elisp page "Search-based
  ;; Fontification").  The font lock region is delimited by POINT and the
  ;; single parameter, LIMIT.  Each of these functions returns NIL (thus
  ;; inhibiting spurious font-lock-keyword-face highlighting and another
  ;; call).

  t `(;; Initialize some things before the search functions below.
      c-font-lock-complex-decl-prepare

      ,@(if (c-major-mode-is 'objc-mode)
	    ;; Fontify method declarations in Objective-C, but first
	    ;; we have to put the `c-decl-end' `c-type' property on
	    ;; all the @-style directives that haven't been handled in
	    ;; `c-basic-matchers-before'.
	    `(,(c-make-font-lock-search-function
		(c-make-keywords-re t
		  ;; Exclude "@class" since that directive ends with a
		  ;; semicolon anyway.
		  (delete "@class"
			  (append (c-lang-const c-protection-kwds)
				  (c-lang-const c-other-decl-kwds)
				  nil)))
		'((c-put-char-property (1- (match-end 1))
				       'c-type 'c-decl-end)))
	      c-font-lock-objc-methods))

      ;; Fontify declarators which have been cut off from their declaring
      ;; types at the start of the region.
      c-font-lock-cut-off-declarators

      ;; Fontify all declarations, casts and normal labels.
      c-font-lock-declarations

      ;; Fontify declarators when POINT is within their declaration.
      c-font-lock-enclosing-decls

      ;; Fontify angle bracket arglists like templates in C++.
      ,@(when (c-lang-const c-recognize-<>-arglists)
	  '(c-font-lock-<>-arglists))

      ,@(when (c-major-mode-is 'c++-mode)
	  '(c-font-lock-c++-lambda-captures))

      ,@(when (c-lang-const c-using-key)
	  `(c-font-lock-c++-using))

      ;; The first two rules here mostly find occurrences that
      ;; `c-font-lock-declarations' has found already, but not
      ;; declarations containing blocks in the type (see note below).
      ;; It's also useful to fontify these everywhere to show e.g. when
      ;; a type keyword is accidentally used as an identifier.

      ;; Fontify basic types.
      ,(let ((re (c-make-keywords-re nil
		   (c--delete-duplicates
		    (append (c-lang-const c-primitive-type-kwds)
			    (c-lang-const c-type-with-paren-kwds))
		    :test #'equal))))
	 (if (c-major-mode-is 'pike-mode)
	     ;; No symbol is a keyword after "->" in Pike.
	     `(,(concat "\\(\\=.?\\|[^>]\\|[^-]>\\)"
			"\\_<\\(" re "\\)\\_>")
	       2 font-lock-type-face)
	   `(,(concat "\\_<\\(" re "\\)\\_>")
	     1 'font-lock-type-face)))
      ;; Fontify the type in C++ "new" expressions.
      ,@(when (c-major-mode-is 'c++-mode)
	  ;; This pattern is a probably a "(MATCHER . ANCHORED-HIGHLIGHTER)"
	  ;; (see Elisp page "Search-based Fontification").
	  `(("\\_<new\\_>"
	     (c-font-lock-c++-new))))

      ;; Maybe fontify identifiers containing a dollar sign with
      ;; `font-lock-warning-face'.
      ,@(when (c-lang-const c-dollar-in-ids)
	  `(c-font-lock-ids-with-dollar))))

(defun c-font-lock-labels (limit)
  ;; Fontify all statement labels from the point to LIMIT.  Assumes
  ;; that strings and comments have been fontified already.  Nil is
  ;; always returned.
  ;;
  ;; Note: This function is only used on decoration level 2; this is
  ;; taken care of directly by the gargantuan
  ;; `c-font-lock-declarations' on higher levels.
  ;;
  ;; This function might do hidden buffer changes.

  (let (continue-pos id-start
	;; The font-lock package in Emacs is known to clobber
	;; `parse-sexp-lookup-properties' (when it exists).
	(parse-sexp-lookup-properties
	 (cc-eval-when-compile
	   (boundp 'parse-sexp-lookup-properties))))

    (while (re-search-forward ":[^:]" limit t)
      (setq continue-pos (point))
      (goto-char (match-beginning 0))
      (unless (c-skip-comments-and-strings limit)

	(c-backward-syntactic-ws)
	(and (setq id-start (c-on-identifier))

	     (not (get-text-property id-start 'face))

	     (progn
	       (goto-char id-start)
	       (c-backward-syntactic-ws)
	       (or
		;; Check for a char that precedes a statement.
		(memq (char-before) '(?\} ?\{ ?\;))
		;; Check for a preceding label.  We exploit the font
		;; locking made earlier by this function.
		(and (eq (char-before) ?:)
		     (progn
		       (backward-char)
		       (c-backward-syntactic-ws)
		       (not (bobp)))
		     (eq (get-text-property (1- (point)) 'face)
			 c-label-face-name))
		;; Check for a keyword that precedes a statement.
		(c-after-conditional)))

	     (progn
	       ;; Got a label.
	       (goto-char id-start)
	       (looking-at c-symbol-key)
	       (c-put-font-lock-face (match-beginning 0) (match-end 0)
				     c-label-face-name)))

	(goto-char continue-pos))))
  nil)

(c-lang-defconst c-basic-matchers-after
  "Font lock matchers for various things that should be fontified after
generic casts and declarations are fontified.  Used on level 2 and
higher."

  t `(,@(when (c-lang-const c-enum-list-kwds)
      ;; Fontify the remaining identifiers inside an enum list when we start
      ;; inside it.
	  '(c-font-lock-enum-tail
	    ;; Fontify the identifiers inside enum lists.  (The enum type
	    ;; name is handled by `c-simple-decl-matchers' or
	    ;; `c-complex-decl-matchers' below.
	    c-font-lock-enum-body))

	;; Fontify labels after goto etc.
	,@(when (c-lang-const c-before-label-kwds)
	  `(;; (Got three different interpretation levels here,
	    ;; which makes it a bit complicated: 1) The backquote
	    ;; stuff is expanded when compiled or loaded, 2) the
	    ;; eval form is evaluated at font-lock setup (to
	    ;; substitute c-label-face-name correctly), and 3) the
	    ;; resulting structure is interpreted during
	    ;; fontification.)
	    (eval
	     . ,(let* ((c-before-label-re
			(c-make-keywords-re nil
			  (c-lang-const c-before-label-kwds))))
		  `(list
		    ,(concat "\\_<\\(" c-before-label-re "\\)\\_>"
			     "\\s *"
			     "\\("	; identifier-offset
			     (c-lang-const c-symbol-key)
			     "\\)")
		    (list ,(+ (regexp-opt-depth c-before-label-re) 2)
			  c-label-face-name nil t))))))

      ;; Fontify the clauses after various keywords.
	,@(when (or (c-lang-const c-type-list-kwds)
		    (c-lang-const c-ref-list-kwds)
		    (c-lang-const c-colon-type-list-kwds))
	    `((,(c-make-font-lock-BO-decl-search-function
		 (concat "\\_<\\("
			 (c-make-keywords-re nil
			   (append (c-lang-const c-type-list-kwds)
				   (c-lang-const c-ref-list-kwds)
				   (c-lang-const c-colon-type-list-kwds)))
			 "\\)\\_>")
		 '((c-fontify-types-and-refs ((c-promote-possible-types t))
		     (c-forward-keyword-clause 1)
		     (if (> (point) limit) (goto-char limit))))))))

	,@(when (c-lang-const c-paren-type-kwds)
	    `((,(c-make-font-lock-search-function
		 (concat "\\_<\\("
			 (c-make-keywords-re nil
			   (c-lang-const c-paren-type-kwds))
			 "\\)\\_>")
		 '((c-fontify-types-and-refs ((c-promote-possible-types t))
		     (c-forward-keyword-clause 1)
		     (if (> (point) limit) (goto-char limit))))))))

	,@(when (c-major-mode-is 'java-mode)
	    '((eval . (list "\\_<\\(@[a-zA-Z0-9]+\\)\\_>" 1 c-annotation-face))))
	))

(c-lang-defconst c-matchers-1
  t (c-lang-const c-cpp-matchers))

(c-lang-defconst c-matchers-2
  t (append (c-lang-const c-matchers-1)
	    (c-lang-const c-basic-matchers-before)
	    (c-lang-const c-simple-decl-matchers)
	    (c-lang-const c-basic-matchers-after)))

(c-lang-defconst c-matchers-3
  t (append (c-lang-const c-matchers-1)
	    (c-lang-const c-basic-matchers-before)
	    (c-lang-const c-complex-decl-matchers)
	    (c-lang-const c-basic-matchers-after)))

(defun c-get-doc-comment-style ()
  ;; Get the symbol (or list of symbols) constituting the document style.
  ;; Return nil if there is no such, otherwise something like `autodoc'.
  (if (consp (car-safe c-doc-comment-style))
      (cdr-safe (or (assq c-buffer-is-cc-mode c-doc-comment-style)
		    (assq 'other c-doc-comment-style)))
    c-doc-comment-style))

(defun c-compose-keywords-list (base-list)
  ;; Incorporate the font lock keyword lists according to
  ;; `c-doc-comment-style' on the given keyword list and return it.
  ;; This is used in the function bindings of the
  ;; `*-font-lock-keywords-*' symbols since we have to build the list
  ;; when font-lock is initialized.

  (unless (memq c-doc-face-name c-literal-faces)
    (setq c-literal-faces (cons c-doc-face-name c-literal-faces)))

  (let* ((doc-keywords (c-get-doc-comment-style))
	 (list (nconc (c--mapcan
		       (lambda (doc-style)
			 (let ((sym (intern
				     (concat (symbol-name doc-style)
					     "-font-lock-keywords"))))
			   (cond ((fboundp sym)
				  (funcall sym))
				 ((boundp sym)
				  (append (eval sym) nil)))))
		       (if (listp doc-keywords)
			   doc-keywords
			 (list doc-keywords)))
		      base-list)))

    ;; Kludge: If `c-font-lock-complex-decl-prepare' is on the list we
    ;; move it first since the doc comment font lockers might add
    ;; `c-type' text properties, so they have to be cleared before that.
    (when (memq 'c-font-lock-complex-decl-prepare list)
      (setq list (cons 'c-font-lock-complex-decl-prepare
		       (delq 'c-font-lock-complex-decl-prepare
			     (append list nil)))))

    list))

(defun c-override-default-keywords (def-var)
  ;; This is used to override the value on a `*-font-lock-keywords'
  ;; variable only if it's nil or has the same value as one of the
  ;; `*-font-lock-keywords-*' variables.  Older font-lock packages
  ;; define a default value for `*-font-lock-keywords' which we want
  ;; to override, but we should otoh avoid clobbering a user setting.
  ;; This heuristic for that isn't perfect, but I can't think of any
  ;; better. /mast
  (when (and (boundp def-var)
	     (memq (symbol-value def-var)
		   (cons nil
			 (mapcar
			  (lambda (suffix)
			    (let ((sym (intern (concat (symbol-name def-var)
						       suffix))))
			      (and (boundp sym) (symbol-value sym))))
			  '("-1" "-2" "-3")))))
    ;; The overriding is done by unbinding the variable so that the normal
    ;; defvar will install its default value later on.
    (makunbound def-var)))

;; `c-re-redisplay-timer' is a timer which, when triggered, causes a
;; redisplay.
(defvar c-re-redisplay-timer nil)

(defun c-force-redisplay (buffer start end)
  ;; Force redisplay immediately.  This assumes `font-lock-support-mode' is
  ;; 'jit-lock-mode.  Set the variable `c-re-redisplay-timer' to nil.
  (with-current-buffer buffer
    (save-excursion (c-font-lock-fontify-region start end))
    (jit-lock-force-redisplay (copy-marker start) (copy-marker end))
    (setq c-re-redisplay-timer nil)))

(defun c-fontify-new-found-type (type)
  ;; Cause the fontification of TYPE, a string, wherever it occurs in the
  ;; buffer.  If TYPE is currently displayed in a window, cause redisplay to
  ;; happen "instantaneously".  These actions are done only when jit-lock-mode
  ;; is active.
  (when (and font-lock-mode
	     (boundp 'font-lock-support-mode)
	     (eq font-lock-support-mode 'jit-lock-mode))
    (c-save-buffer-state
	((window-boundaries
	  (mapcar (lambda (win)
		    (cons (window-start win)
			  (window-end win)))
		  (get-buffer-window-list (current-buffer) 'no-mini t)))
	 (target-re (concat "\\_<" type "\\_>")))
      (save-excursion
	(save-restriction
	  (widen)
	  (goto-char (point-min))
	  (while (re-search-forward target-re nil t)
	    (when (and
		   (get-text-property (match-beginning 0) 'fontified)
		   (not (memq (c-get-char-property (match-beginning 0) 'face)
			      c-literal-faces)))
	      (put-text-property (match-beginning 0) (match-end 0)
				 'fontified nil))
	    (dolist (win-boundary window-boundaries)
	      (when (and (< (match-beginning 0) (cdr win-boundary))
			 (> (match-end 0) (car win-boundary))
			 (not c-re-redisplay-timer))
		(setq c-re-redisplay-timer
		      (run-with-timer 0 nil #'c-force-redisplay
				      (current-buffer)
				      (match-beginning 0) (match-end 0)))))))))))


;;; C.

(c-override-default-keywords 'c-font-lock-keywords)

(defconst c-font-lock-keywords-1 (c-lang-const c-matchers-1 c)
  "Minimal font locking for C mode.
Fontifies only preprocessor directives (in addition to the syntactic
fontification of strings and comments).")

(defconst c-font-lock-keywords-2 (c-lang-const c-matchers-2 c)
  "Fast normal font locking for C mode.
In addition to `c-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `c-font-lock-extra-types', and the doc comment
styles specified by `c-doc-comment-style'.")

(defconst c-font-lock-keywords-3 (c-lang-const c-matchers-3 c)
  "Accurate normal font locking for C mode.
Like the variable `c-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `c-font-lock-extra-types'.")

(defvar c-font-lock-keywords c-font-lock-keywords-3
  "Default expressions to highlight in C mode.")

(defun c-font-lock-keywords-2 ()
  (c-compose-keywords-list c-font-lock-keywords-2))
(defun c-font-lock-keywords-3 ()
  (c-compose-keywords-list c-font-lock-keywords-3))
(defun c-font-lock-keywords ()
  (c-compose-keywords-list c-font-lock-keywords))


;;; C++.
(defun c-font-lock-c++-using (limit)
  ;; Fontify any clauses starting with the keyword `using'.
  ;;
  ;; This function will be called from font-lock- for a region bounded by
  ;; POINT and LIMIT, as though it were to identify a keyword for
  ;; font-lock-keyword-face.  It always returns NIL to inhibit this and
  ;; prevent a repeat invocation.  See elisp/lispref page "Search-based
  ;; fontification".
  (let (pos)
    (while
	(and (< (point) limit)
	     (c-syntactic-re-search-forward c-using-key limit 'end))
      (while  ; Do one declarator of a comma separated list, each time around.
	  (progn
	    (c-forward-syntactic-ws)
	    (setq pos (point))		; token after "using".
	    (when (and (c-on-identifier)
		       (c-forward-name))
	      (cond
	       ((eq (char-after) ?=)		; using foo = <type-id>;
		(goto-char pos)
		(c-font-lock-declarators limit nil t nil))
	       ((save-excursion
		  (and c-colon-type-list-re
		       (c-go-up-list-backward)
		       (eq (char-after) ?{)
		       (eq (car (c-beginning-of-decl-1
				 (c-determine-limit 1000)))
			   'same)
		       (looking-at c-colon-type-list-re)))
		;; Inherited protected member: leave unfontified
		))
	      (eq (char-after) ?,)))
	(forward-char)))		; over the comma.
    nil))

(defun c-font-lock-c++-new (limit)
  ;; FIXME!!!  Put in a comment about the context of this function's
  ;; invocation.  I think it's called as an ANCHORED-MATCHER within an
  ;; ANCHORED-HIGHLIGHTER.  (2007/2/10).
  ;;
  ;; Assuming point is after a "new" word, check that it isn't inside
  ;; a string or comment, and if so try to fontify the type in the
  ;; allocation expression.  Nil is always returned.
  ;;
  ;; As usual, C++ takes the prize in coming up with a hard to parse
  ;; syntax. :P
  ;;
  ;; This function might do hidden buffer changes.

  (unless (c-skip-comments-and-strings limit)
    (save-excursion
      (catch 'false-alarm
	;; A "new" keyword is followed by one to three expressions, where
	;; the type is the middle one, and the only required part.
	(let (expr1-pos expr2-pos
	      ;; Enable recording of identifier ranges in `c-forward-type'
	      ;; etc for later fontification.  Not using
	      ;; `c-fontify-types-and-refs' here since the ranges should
	      ;; be fontified selectively only when an allocation
	      ;; expression is successfully recognized.
	      (c-record-type-identifiers t)
	      c-record-ref-identifiers
	      ;; The font-lock package in Emacs is known to clobber
	      ;; `parse-sexp-lookup-properties' (when it exists).
	      (parse-sexp-lookup-properties
	       (cc-eval-when-compile
		 (boundp 'parse-sexp-lookup-properties))))
	  (c-forward-syntactic-ws)

	  ;; The first placement arglist is always parenthesized, if it
	  ;; exists.
	  (when (eq (char-after) ?\()
	    (setq expr1-pos (1+ (point)))
	    (condition-case nil
		(c-forward-sexp)
	      (scan-error (throw 'false-alarm t)))
	    (c-forward-syntactic-ws))

	  ;; The second expression is either a type followed by some "*" or
	  ;; "[...]" or similar, or a parenthesized type followed by a full
	  ;; identifierless declarator.
	  (setq expr2-pos (1+ (point)))
	  (cond ((eq (char-after) ?\())
		((let ((c-promote-possible-types t))
		   (c-forward-type)))
		(t (setq expr2-pos nil)))

	  (when expr1-pos
	    (cond
	     ((not expr2-pos)
	      ;; No second expression, so the first has to be a
	      ;; parenthesized type.
	      (goto-char expr1-pos)
	      (let ((c-promote-possible-types t))
		(c-forward-type)))

	     ((eq (char-before expr2-pos) ?\()
	      ;; Got two parenthesized expressions, so we have to look
	      ;; closer at them to decide which is the type.  No need to
	      ;; handle `c-record-ref-identifiers' since all references
	      ;; have already been handled by other fontification rules.
	      (let (expr1-res expr2-res)

		(goto-char expr1-pos)
		(when (setq expr1-res (c-forward-type))
		  (unless (looking-at
			   (cc-eval-when-compile
			     (concat (c-lang-const c-symbol-start c++)
				     "\\|[*:)[]")))
		    ;; There's something after the would-be type that
		    ;; can't be there, so this is a placement arglist.
		    (setq expr1-res nil)))

		(goto-char expr2-pos)
		(when (setq expr2-res (c-forward-type))
		  (unless (looking-at
			   (cc-eval-when-compile
			     (concat (c-lang-const c-symbol-start c++)
				     "\\|[*:)[]")))
		    ;; There's something after the would-be type that can't
		    ;; be there, so this is an initialization expression.
		    (setq expr2-res nil))
		  (when (and (c-go-up-list-forward)
			     (progn (c-forward-syntactic-ws)
				    (eq (char-after) ?\()))
		    ;; If there's a third initialization expression
		    ;; then the second one is the type, so demote the
		    ;; first match.
		    (setq expr1-res nil)))

		;; We fontify the most likely type, with a preference for
		;; the first argument since a placement arglist is more
		;; unusual than an initializer.
		(cond ((memq expr1-res '(t known prefix)))
		      ((memq expr2-res '(t known prefix)))
		      ;; Presumably 'decltype's will be fontified elsewhere.
		      ((eq expr1-res 'decltype))
		      ((eq expr2-res 'decltype))
		      ((eq expr1-res 'found)
		       (let ((c-promote-possible-types t))
			 (goto-char expr1-pos)
			 (c-forward-type)))
		      ((eq expr2-res 'found)
		       (let ((c-promote-possible-types t))
			 (goto-char expr2-pos)
			 (c-forward-type)))
		      ((and (eq expr1-res 'maybe) (not expr2-res))
		       (let ((c-promote-possible-types t))
			 (goto-char expr1-pos)
			 (c-forward-type)))
		      ((and (not expr1-res) (eq expr2-res 'maybe))
		       (let ((c-promote-possible-types t))
			 (goto-char expr2-pos)
			 (c-forward-type)))
		      ;; If both type matches are 'maybe then we're
		      ;; too uncertain to promote either of them.
		      )))))

	  ;; Fontify the type that now is recorded in
	  ;; `c-record-type-identifiers', if any.
	  (c-fontify-recorded-types-and-refs)))))
  nil)

(c-override-default-keywords 'c++-font-lock-keywords)

(defconst c++-font-lock-keywords-1 (c-lang-const c-matchers-1 c++)
  "Minimal font locking for C++ mode.
Fontifies only preprocessor directives (in addition to the syntactic
fontification of strings and comments).")

(defconst c++-font-lock-keywords-2 (c-lang-const c-matchers-2 c++)
  "Fast normal font locking for C++ mode.
In addition to `c++-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `c++-font-lock-extra-types', and the doc comment
styles specified by `c-doc-comment-style'.")

(defconst c++-font-lock-keywords-3 (c-lang-const c-matchers-3 c++)
  "Accurate normal font locking for C++ mode.
Like the variable `c++-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `c++-font-lock-extra-types'.")

(defvar c++-font-lock-keywords c++-font-lock-keywords-3
  "Default expressions to highlight in C++ mode.")

(defun c++-font-lock-keywords-2 ()
  (c-compose-keywords-list c++-font-lock-keywords-2))
(defun c++-font-lock-keywords-3 ()
  (c-compose-keywords-list c++-font-lock-keywords-3))
(defun c++-font-lock-keywords ()
  (c-compose-keywords-list c++-font-lock-keywords))


;;; Objective-C.

(defun c-font-lock-objc-method ()
  ;; Assuming the point is after the + or - that starts an Objective-C
  ;; method declaration, fontify it.  This must be done before normal
  ;; casts, declarations and labels are fontified since they will get
  ;; false matches in these things.
  ;;
  ;; This function might do hidden buffer changes.

  (c-fontify-types-and-refs
      ((first t)
       (c-promote-possible-types t))

    (while (and
	    (progn
	      (c-forward-syntactic-ws)

	      ;; An optional method type.
	      (if (eq (char-after) ?\()
		  (progn
		    (forward-char)
		    (c-forward-syntactic-ws)
		    (c-forward-type)
		    (prog1 (c-go-up-list-forward)
		      (c-forward-syntactic-ws)))
		t))

	    ;; The name.  The first time it's the first part of
	    ;; the function name, the rest of the time it's an
	    ;; argument name.
	    (looking-at c-symbol-key)
	    (progn
	      (goto-char (match-end 0))
	      (c-put-font-lock-face (match-beginning 0)
				    (point)
				    (if first
					'font-lock-function-name-face
				      'font-lock-variable-name-face))
	      (c-forward-syntactic-ws)

	      ;; Another optional part of the function name.
	      (when (looking-at c-symbol-key)
		(goto-char (match-end 0))
		(c-put-font-lock-face (match-beginning 0)
				      (point)
				      'font-lock-function-name-face)
		(c-forward-syntactic-ws))

	      ;; There's another argument if a colon follows.
	      (eq (char-after) ?:)))
      (forward-char)
      (setq first nil))))

(defun c-font-lock-objc-methods (limit)
  ;; Fontify method declarations in Objective-C.  Nil is always
  ;; returned.
  ;;
  ;; This function might do hidden buffer changes.

  (let (;; The font-lock package in Emacs is known to clobber
	;; `parse-sexp-lookup-properties' (when it exists).
	(parse-sexp-lookup-properties
	 (cc-eval-when-compile
	   (boundp 'parse-sexp-lookup-properties))))

    (c-find-decl-spots
     limit
     "[-+]"
     nil
     (lambda (_match-pos _inside-macro &optional _top-level)
       (forward-char)
       (c-font-lock-objc-method))))
  nil)

(c-override-default-keywords 'objc-font-lock-keywords)

(defconst objc-font-lock-keywords-1 (c-lang-const c-matchers-1 objc)
  "Minimal font locking for Objective-C mode.
Fontifies only compiler directives (in addition to the syntactic
fontification of strings and comments).")

(defconst objc-font-lock-keywords-2 (c-lang-const c-matchers-2 objc)
  "Fast normal font locking for Objective-C mode.
In addition to `objc-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `objc-font-lock-extra-types', and the doc
comment styles specified by `c-doc-comment-style'.")

(defconst objc-font-lock-keywords-3 (c-lang-const c-matchers-3 objc)
  "Accurate normal font locking for Objective-C mode.
Like the variable `objc-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `objc-font-lock-extra-types'.")

(defvar objc-font-lock-keywords objc-font-lock-keywords-3
  "Default expressions to highlight in Objective-C mode.")

(defun objc-font-lock-keywords-2 ()
  (c-compose-keywords-list objc-font-lock-keywords-2))
(defun objc-font-lock-keywords-3 ()
  (c-compose-keywords-list objc-font-lock-keywords-3))
(defun objc-font-lock-keywords ()
  (c-compose-keywords-list objc-font-lock-keywords))

;; Kludge to override the default value that
;; `objc-font-lock-extra-types' might have gotten from the font-lock
;; package.  The value replaced here isn't relevant now anyway since
;; those types are builtin and therefore listed directly in
;; `c-primitive-type-kwds'.
(when (equal (sort (append objc-font-lock-extra-types nil) 'string-lessp)
	     '("BOOL" "Class" "IMP" "SEL"))
  (setq objc-font-lock-extra-types
	(cc-eval-when-compile (list (concat "[" c-upper "]\\sw*")))))


;;; Java.

(c-override-default-keywords 'java-font-lock-keywords)

(defconst java-font-lock-keywords-1 (c-lang-const c-matchers-1 java)
  "Minimal font locking for Java mode.
Fontifies nothing except the syntactic fontification of strings and
comments.")

(defconst java-font-lock-keywords-2 (c-lang-const c-matchers-2 java)
  "Fast normal font locking for Java mode.
In addition to `java-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `java-font-lock-extra-types', and the doc
comment styles specified by `c-doc-comment-style'.")

(defconst java-font-lock-keywords-3 (c-lang-const c-matchers-3 java)
  "Accurate normal font locking for Java mode.
Like variable `java-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `java-font-lock-extra-types'.")

(defvar java-font-lock-keywords java-font-lock-keywords-3
  "Default expressions to highlight in Java mode.")

(defun java-font-lock-keywords-2 ()
  (c-compose-keywords-list java-font-lock-keywords-2))
(defun java-font-lock-keywords-3 ()
  (c-compose-keywords-list java-font-lock-keywords-3))
(defun java-font-lock-keywords ()
  (c-compose-keywords-list java-font-lock-keywords))


;;; CORBA IDL.

(c-override-default-keywords 'idl-font-lock-keywords)

(defconst idl-font-lock-keywords-1 (c-lang-const c-matchers-1 idl)
  "Minimal font locking for CORBA IDL mode.
Fontifies nothing except the syntactic fontification of strings and
comments.")

(defconst idl-font-lock-keywords-2 (c-lang-const c-matchers-2 idl)
  "Fast normal font locking for CORBA IDL mode.
In addition to `idl-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `idl-font-lock-extra-types', and the doc comment
styles specified by `c-doc-comment-style'.")

(defconst idl-font-lock-keywords-3 (c-lang-const c-matchers-3 idl)
  "Accurate normal font locking for CORBA IDL mode.
Like the variable `idl-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `idl-font-lock-extra-types'.")

(defvar idl-font-lock-keywords idl-font-lock-keywords-3
  "Default expressions to highlight in CORBA IDL mode.")

(defun idl-font-lock-keywords-2 ()
  (c-compose-keywords-list idl-font-lock-keywords-2))
(defun idl-font-lock-keywords-3 ()
  (c-compose-keywords-list idl-font-lock-keywords-3))
(defun idl-font-lock-keywords ()
  (c-compose-keywords-list idl-font-lock-keywords))


;;; Pike.

(c-override-default-keywords 'pike-font-lock-keywords)

(defconst pike-font-lock-keywords-1 (c-lang-const c-matchers-1 pike)
  "Minimal font locking for Pike mode.
Fontifies only preprocessor directives (in addition to the syntactic
fontification of strings and comments).")

(defconst pike-font-lock-keywords-2 (c-lang-const c-matchers-2 pike)
  "Fast normal font locking for Pike mode.
In addition to `pike-font-lock-keywords-1', this adds fontification of
keywords, simple types, declarations that are easy to recognize, the
user defined types on `pike-font-lock-extra-types', and the doc
comment styles specified by `c-doc-comment-style'.")

(defconst pike-font-lock-keywords-3 (c-lang-const c-matchers-3 pike)
  "Accurate normal font locking for Pike mode.
Like the variable `pike-font-lock-keywords-2' but detects declarations in a more
accurate way that works in most cases for arbitrary types without the
need for `pike-font-lock-extra-types'.")

(defvar pike-font-lock-keywords pike-font-lock-keywords-3
  "Default expressions to highlight in Pike mode.")

(defun pike-font-lock-keywords-2 ()
  (c-set-doc-comment-res)
  (c-compose-keywords-list pike-font-lock-keywords-2))
(defun pike-font-lock-keywords-3 ()
  (c-set-doc-comment-res)
  (c-compose-keywords-list pike-font-lock-keywords-3))
(defun pike-font-lock-keywords ()
  (c-set-doc-comment-res)
  (c-compose-keywords-list pike-font-lock-keywords))


;;; Doc comments.

(cc-bytecomp-defvar c-doc-line-join-re)
;; matches a join of two lines in a doc comment.
;; This should not be changed directly, but instead set by
;; `c-setup-doc-comment-style'.  This variable is used in `c-find-decl-spots'
;; in (e.g.) autodoc style comments to bridge the gap between a "@\n" at an
;; EOL and the token following "//!" on the next line.

(cc-bytecomp-defvar c-doc-bright-comment-start-re)
;; Matches the start of a "bright" comment, one whose contents may be
;; fontified by, e.g., `c-font-lock-declarations'.

(cc-bytecomp-defvar c-doc-line-join-end-ch)
;; A list of characters, each being a last character of a doc comment marker,
;; e.g. the ! from pike autodoc's "//!".

(defmacro c-set-doc-comment-re-element (suffix)
  ;; Set the variable `c-doc-line-join-re' to a buffer local value suitable
  ;; for the current doc comment style, or kill the local value.
  (declare (debug t))
  (let ((var (intern (concat "c-doc" suffix))))
    `(let* ((styles (c-get-doc-comment-style))
	    elts)
       (when (atom styles)
	 (setq styles (list styles)))
       (setq elts
	     (mapcar (lambda (style)
		       (let ((sym
			      (intern-soft
			       (concat (symbol-name style) ,suffix))))
			 (and sym
			      (boundp sym)
			      (symbol-value sym))))
		     styles))
       (setq elts (delq nil elts))
       (setq elts (and elts
		       (concat "\\("
			       (mapconcat #'identity elts "\\|")
			       "\\)")))
       (if elts
	   (set (make-local-variable ',var) elts)
	 (kill-local-variable ',var)))))

(defmacro c-set-doc-comment-char-list (suffix)
  ;; Set the variable 'c-doc-<suffix>' to the list of *-<suffix>, which must
  ;; be characters, and * represents the doc comment style.
  (declare (debug t))
  (let ((var (intern (concat "c-doc" suffix))))
    `(let* ((styles (c-get-doc-comment-style))
	    elts)
       (when (atom styles)
	 (setq styles (list styles)))
       (setq elts
	     (mapcar (lambda (style)
		       (let ((sym
			      (intern-soft
			       (concat (symbol-name style) ,suffix))))
			 (and sym
			      (boundp sym)
			      (symbol-value sym))))
		     styles))
       (setq elts (delq nil elts))
       (if elts
	   (set (make-local-variable ',var) elts)
	 (kill-local-variable ',var)))))

(defun c-set-doc-comment-res ()
  ;; Set the variables `c-doc-line-join-re' and
  ;; `c-doc-bright-comment-start-re' from the current doc comment style(s).
  (c-set-doc-comment-re-element "-line-join-re")
  (c-set-doc-comment-re-element "-bright-comment-start-re")
  (c-set-doc-comment-char-list "-line-join-end-ch"))

(defun c-font-lock-doc-comments (prefix limit keywords)
  ;; Fontify the comments between the point and LIMIT whose start
  ;; matches PREFIX with `c-doc-face-name'.  Assumes comments have been
  ;; fontified with `font-lock-comment-face' already.  nil is always
  ;; returned.
  ;;
  ;; After the fontification of a matching comment, fontification
  ;; according to KEYWORDS is applied inside it.  It's a list like
  ;; `font-lock-keywords' except that anchored matches and eval
  ;; clauses aren't supported and that some abbreviated forms can't be
  ;; used.  The buffer is narrowed to the comment while KEYWORDS is
  ;; applied; leading comment starters are included but trailing
  ;; comment enders for block comment are not.
  ;;
  ;; Note that faces added through KEYWORDS should never replace the
  ;; existing `c-doc-face-name' face since the existence of that face
  ;; is used as a flag in other code to skip comments.
  ;;
  ;; This function might do hidden buffer changes.
  (declare (indent 2))
  (let (comment-beg region-beg comment-mid)
    (if (memq (get-text-property (point) 'face)
	      '(font-lock-comment-face font-lock-comment-delimiter-face))
	;; Handle the case when the fontified region starts inside a
	;; comment.
	(let ((start (c-literal-start)))
	  (setq region-beg (point)
		comment-mid (point))
	  (when start
	    (goto-char start))
	  (when (looking-at prefix)
	    (setq comment-beg (point)))))

    (while (or
	    comment-beg

	    ;; Search for the prefix until a match is found at the start
	    ;; of a comment.
	    (while (when (re-search-forward prefix limit t)
		     (setq comment-beg (match-beginning 0))
		     (or (not (c-got-face-at comment-beg
					     c-literal-faces))
			 (and (/= comment-beg (point-min))
			      ;; Cheap check which is unreliable (the previous
			      ;; character could be the end of a previous
			      ;; comment).
			      (c-got-face-at (1- comment-beg)
					     c-literal-faces)
			      ;; Expensive reliable check.
			      (save-excursion
				(goto-char comment-beg)
				(c-in-literal)))))
	      (setq comment-beg nil))
	    (setq region-beg comment-beg
		  comment-mid comment-beg))

      (if (elt (parse-partial-sexp comment-beg (+ comment-beg 2)) 7)
	  ;; Collect a sequence of doc style line comments.
	  (progn
	    (goto-char comment-beg)
	    (while (and (progn
			  (c-forward-single-comment)
			  (c-put-font-lock-face comment-mid (point)
						c-doc-face-name)
			  (skip-syntax-forward " ")
			  (setq comment-beg (point)
				comment-mid (point))
			  (< (point) limit))
			(looking-at prefix))))
	(goto-char comment-beg)
	(c-forward-single-comment)
	(c-put-font-lock-face region-beg (point) c-doc-face-name))
      (if (> (point) limit) (goto-char limit))
      (setq comment-beg nil)

      (let ((region-end (point))
	    (keylist keywords) keyword matcher highlights)
	(save-restriction
	  ;; Narrow to the doc comment.  Among other things, this
	  ;; helps by making "^" match at the start of the comment.
	  ;; Do not include a trailing block comment ender, though.
	  (and (> region-end (1+ region-beg))
	       (progn (goto-char region-end)
		      (backward-char 2)
		      (looking-at "\\*/"))
	       (setq region-end (point)))
	  (narrow-to-region region-beg region-end)

	  (while keylist
	    (setq keyword (car keylist)
		  keylist (cdr keylist)
		  matcher (car keyword))
	    (goto-char region-beg)
	    (while (if (stringp matcher)
		       (re-search-forward matcher region-end t)
		     (funcall matcher region-end))
	      (setq highlights (cdr keyword))
	      (if (consp (car highlights))
		  (while highlights
		    (font-lock-apply-highlight (car highlights))
		    (setq highlights (cdr highlights)))
		(font-lock-apply-highlight highlights))))

	  (goto-char region-end)))))
  nil)

(defun c-find-invalid-doc-markup (regexp limit)
  ;; Used to fontify invalid markup in doc comments after the correct
  ;; ones have been fontified: Find the first occurrence of REGEXP
  ;; between the point and LIMIT that only is fontified with
  ;; `c-doc-face-name'.  If a match is found then submatch 0 surrounds
  ;; the first char and t is returned, otherwise nil is returned.
  ;;
  ;; This function might do hidden buffer changes.
  (let (start)
    (while (if (re-search-forward regexp limit t)
	       (not (eq (get-text-property
			 (setq start (match-beginning 0)) 'face)
			c-doc-face-name))
	     (setq start nil)))
    (when start
      (store-match-data (list (copy-marker start)
			      (copy-marker (1+ start))))
      t)))

;; GtkDoc patterns contributed by Masatake YAMATO <yamato@redhat.com>.

(defconst gtkdoc-font-lock-doc-comments
  (let ((symbol "[a-zA-Z0-9_]+")
	(header "^ \\* "))
    `((,(concat header "\\("     symbol "\\):[ \t]*$")
       1 ,c-doc-markup-face-name prepend nil)
      (,(concat                  symbol     "()")
       0 ,c-doc-markup-face-name prepend nil)
      (,(concat header "\\(" "@" symbol "\\):")
       1 ,c-doc-markup-face-name prepend nil)
      (,(concat "[#%@]" symbol)
       0 ,c-doc-markup-face-name prepend nil))
    ))

(defconst gtkdoc-font-lock-doc-protection
  `(("< \\(public\\|private\\|protected\\) >"
     1 ,c-doc-markup-face-name prepend nil)))

(defconst gtkdoc-font-lock-keywords
  `((,(lambda (limit)
	(c-font-lock-doc-comments "/\\*\\*\\([^*/\n\r].*\\)?$" limit
	  gtkdoc-font-lock-doc-comments)
	(c-font-lock-doc-comments "/\\*< " limit
	  gtkdoc-font-lock-doc-protection)
	))))

;; Javadoc.

(defconst javadoc-font-lock-doc-comments
  `(("{@[a-z]+[^}\n\r]*}"		; "{@foo ...}" markup.
     0 ,c-doc-markup-face-name prepend nil)
    ("^\\(/\\*\\)?\\(\\s \\|\\*\\)*\\(@[a-z]+\\)" ; "@foo ..." markup.
     3 ,c-doc-markup-face-name prepend nil)
    (,(concat "</?\\sw"			; HTML tags.
	      "\\("
	      (concat "\\sw\\|\\s \\|[=\n\r*.:]\\|"
		      "\"[^\"]*\"\\|'[^']*'")
	      "\\)*>")
     0 ,c-doc-markup-face-name prepend nil)
    ("&\\(\\sw\\|[.:]\\)+;"		; HTML entities.
     0 ,c-doc-markup-face-name prepend nil)
    ;; Fontify remaining markup characters as invalid.  Note
    ;; that the Javadoc spec is hazy about when "@" is
    ;; allowed in non-markup use.
    (,(lambda (limit)
	(c-find-invalid-doc-markup "[<>&]\\|{@" limit))
     0 'font-lock-warning-face prepend nil)))

(defconst javadoc-font-lock-keywords
  `((,(lambda (limit)
	(c-font-lock-doc-comments "/\\*\\*" limit
	  javadoc-font-lock-doc-comments)))))

;; Pike autodoc.

(defconst autodoc-decl-keywords
  ;; Adorned regexp matching the keywords that introduce declarations
  ;; in Pike Autodoc.
  (cc-eval-when-compile
    (c-make-keywords-re t '("@decl" "@elem" "@index" "@member") 'pike-mode)))

(defconst autodoc-decl-type-keywords
  ;; Adorned regexp matching the keywords that are followed by a type.
  (cc-eval-when-compile
    (c-make-keywords-re t '("@elem" "@member") 'pike-mode)))

(defun autodoc-font-lock-line-markup (limit)
  ;; Fontify all line oriented keywords between the point and LIMIT.
  ;; Nil is always returned.
  ;;
  ;; This function might do hidden buffer changes.

  (let ((line-re (concat "^\\(\\(/\\*!\\|\\s *\\("
			 c-current-comment-prefix
			 "\\)\\)\\s *\\)@[A-Za-z_-]+\\(\\s \\|$\\)"))
	(markup-faces (list c-doc-markup-face-name c-doc-face-name)))

    (while (and (< (point) limit)
		(re-search-forward line-re limit t))
      (goto-char (match-end 1))

      (if (looking-at autodoc-decl-keywords)
	  (let* ((kwd-pos (point))
		 (start (match-end 1))
		 (pos start)
		 end)

	    (c-put-font-lock-face (point) pos markup-faces)

	    ;; Put a declaration end mark at the markup keyword and
	    ;; remove the faces from the rest of the line so that it
	    ;; gets refontified as a declaration later on by
	    ;; `c-font-lock-declarations'.
	    (c-put-char-property (1- pos) 'c-type 'c-decl-end)
	    (goto-char pos)
	    (while (progn
		     (end-of-line)
		     (setq end (point))
		     (and (eq (char-before) ?@)
			  (not (eobp))
			  (progn (forward-char)
				 (skip-syntax-forward " ")
				 (looking-at c-current-comment-prefix))))
	      (goto-char (match-end 0))
	      (c-remove-font-lock-face pos (1- end))
	      (c-put-font-lock-face (1- end) end markup-faces)
	      (setq pos (point)))

	    ;; Include the final newline in the removed area.  This
	    ;; has no visual effect but it avoids some tricky special
	    ;; cases in the testsuite wrt the differences in string
	    ;; fontification in Emacs vs XEmacs.
	    (c-remove-font-lock-face pos (min (1+ (point)) (point-max)))

	    ;; Must handle string literals explicitly inside the declaration.
	    (goto-char start)
	    (while (re-search-forward
		    "\"\\([^\\\"]\\|\\\\.\\)*\"\\|'\\([^\\']\\|\\\\.\\)*'"
		    end 'move)
	      (c-put-font-lock-string-face (match-beginning 0)
					   (point)))

	    ;; Fontify types after keywords that always are followed
	    ;; by them.
	    (goto-char kwd-pos)
	    (when (looking-at autodoc-decl-type-keywords)
	      (c-fontify-types-and-refs ((c-promote-possible-types t))
		(goto-char start)
		(c-forward-syntactic-ws)
		(c-forward-type))))

	;; Mark each whole line as markup, as long as the logical line
	;; continues.
	(while (progn
		 (c-put-font-lock-face (point)
				       (progn (end-of-line) (point))
				       markup-faces)
		 (and (eq (char-before) ?@)
		      (not (eobp))
		      (progn (forward-char)
			     (skip-syntax-forward " ")
			     (looking-at c-current-comment-prefix))))
	  (goto-char (match-end 0))))))

  nil)

(defconst autodoc-font-lock-doc-comments
  `(("@\\(\\w+{\\|\\[\\([^]@\n\r]\\|@@\\)*\\]\\|[@}]\\|$\\)"
     ;; In-text markup.
     0 ,c-doc-markup-face-name prepend nil)
    (autodoc-font-lock-line-markup)
    ;; Fontify remaining markup characters as invalid.
    (,(lambda (limit)
	(c-find-invalid-doc-markup "@" limit))
     0 'font-lock-warning-face prepend nil)
    ))

(defconst autodoc-line-join-re "@[\n\r][ \t]*/[/*]!")
;; Matches a line continuation in autodoc comment style.
(defconst autodoc-bright-comment-start-re "/[/*]!")
;; Matches an autodoc comment opener.
(defconst autodoc-line-join-end-ch ?!)
;; The final character of `autodoc-line-join-re'.

(defun autodoc-font-lock-keywords ()
  ;; Note that we depend on that `c-current-comment-prefix' has got
  ;; its proper value here.
  ;;
  ;; This function might do hidden buffer changes.

  ;; The `c-type' text property with `c-decl-end' is used to mark the
  ;; end of the `autodoc-decl-keywords' occurrences to fontify the
  ;; following declarations.
  (setq c-type-decl-end-used t)

  `((,(lambda (limit)
	(c-font-lock-doc-comments "/[*/]!" limit
	  autodoc-font-lock-doc-comments)))))

;; Doxygen

(defconst doxygen-font-lock-doc-comments
  ;; TODO: Handle @code, @verbatim, @dot, @f etc. better by not highlighting
  ;; text inside of those commands.  Something smarter than just regexes may be
  ;; needed to do that efficiently.
  `((,(concat
       ;; Make sure that the special character has not been escaped.  E.g. in
       ;; `\@foo' only `\@' is a command (similarly for other characters like
       ;; `\\foo', `\<foo' and `\&foo').  The downside now is that we don't
       ;; match command started just after an escaped character, e.g. in
       ;; `\@\foo' we should match `\@' as well as `\foo' but only the former
       ;; is matched.
       "\\(?:^\\|[^\\@]\\)\\("
         ;; Doxygen commands start with backslash or an at sign.  Note that for
         ;; brevity in the comments only `\' will be mentioned.
         "[\\@]\\(?:"
           ;; Doxygen commands except those starting with `f'
           "[a-eg-z][a-z]*"
           ;; Doxygen command starting with `f':
           "\\|f\\(?:"
             "[][$}]"                         ; \f$ \f} \f[ \f]
             "\\|{\\(?:[a-zA-Z]+\\*?}{?\\)?"  ; \f{ \f{env} \f{env}{
             "\\|[a-z]+"                      ; \foo
           "\\)"
           "\\|~[a-zA-Z]*"             ; \~  \~language
           "\\|[$@&~<=>#%\".|\\\\]"    ; single-character escapes
           "\\|::\\|---?"              ; \:: \-- \---
         "\\)"
         ;; HTML tags and entities:
         "\\|</?\\sw\\(?:\\sw\\|\\s \\|[=\n\r*.:]\\|\"[^\"]*\"\\|'[^']*'\\)*>"
         "\\|&\\(?:\\sw+\\|#[0-9]+\\|#x[0-9a-fA-F]+\\);"
       "\\)")
     1 ,c-doc-markup-face-name prepend nil)
    ;; Commands inside of strings are not commands so override highlighting with
    ;; string face.  This also affects HTML attribute values if they are
    ;; surrounded with double quotes which may or may not be considered a good
    ;; thing.
    ("\\(?:^\\|[^\\@]\\)\\(\"[^\"[:cntrl:]]+\"\\)"
     1 font-lock-string-face prepend nil)
    ;; HTML comments inside of the Doxygen comments.
    ("\\(?:^\\|[^\\@]\\)\\(<!--.*?-->\\)"
     1 font-lock-comment-face prepend nil)
    ;; Autolinking. Doxygen auto-links anything that is a class name but we have
    ;; no hope of matching those.  We are, however, able to match functions and
    ;; members using explicit scoped syntax.  For functions, we can also find
    ;; them by noticing argument-list.  Note that Doxygen accepts `::' as well
    ;; as `#' as scope operators.
    (,(let* ((ref "[\\@]ref\\s-+")
             (ref-opt (concat "\\(?:" ref "\\)?"))
             (id "[a-zA-Z_][a-zA-Z_0-9]*")
             (args "\\(?:()\\|([^()]*)\\)")
             (scope "\\(?:#\\|::\\)"))
        (concat
         "\\(?:^\\|[^\\@/%:]\\)\\(?:"
                 ref-opt "\\(?1:" scope "?" "\\(?:" id scope "\\)+" "~?" id "\\)"
           "\\|" ref-opt "\\(?1:" scope     "~?" id "\\)"
           "\\|" ref-opt "\\(?1:" scope "?" "~?" id "\\)" args
           "\\|" ref     "\\(?1:" "~?" id "\\)"
           "\\|" ref-opt "\\(?1:~[A-Z][a-zA-Z0-9_]+\\)"
         "\\)"))
     1 font-lock-function-name-face prepend nil)
    ;; Match URLs and emails.  This has two purposes.  First of all, Doxygen
    ;; autolinks URLs.  Second of all, `@bar' in `foo@bar.baz' has been matched
    ;; above as a command; try and overwrite it.
    (,(let* ((host "[A-Za-z0-9]\\(?:[A-Za-z0-9-]\\{0,61\\}[A-Za-z0-9]\\)")
             (fqdn (concat "\\(?:" host "\\.\\)+" host))
             (comp "[!-(*--/-=?-~]+")
             (path (concat "/\\(?:" comp "[.]+" "\\)*" comp)))
        (concat "\\(?:mailto:\\)?[a-zA-0_.]+@" fqdn
                "\\|https?://" fqdn "\\(?:" path "\\)?"))
     0 font-lock-keyword-face prepend nil)))

(defconst doxygen-font-lock-keywords
  `((,(lambda (limit)
        (c-font-lock-doc-comments "/\\(?:/[/!]\\|\\*[\\*!]\\)"
            limit doxygen-font-lock-doc-comments)))))


;; 2006-07-10:  awk-font-lock-keywords has been moved back to cc-awk.el.
(cc-provide 'cc-fonts)

;; Local Variables:
;; indent-tabs-mode: t
;; tab-width: 8
;; End:
;;; cc-fonts.el ends here
