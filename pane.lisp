;;; -*- Mode: Lisp; Package: CLIMACS-GUI -*-

;;;  (c) copyright 2005 by
;;;           Robert Strandh (strandh@labri.fr)
;;;  (c) copyright 2005 by
;;;           Matthieu Villeneuve (matthieu.villeneuve@free.fr)
;;;  (c) copyright 2005 by
;;;           Aleksandar Bakic (a_bakic@yahoo.com)

;;; This library is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU Library General Public
;;; License as published by the Free Software Foundation; either
;;; version 2 of the License, or (at your option) any later version.
;;;
;;; This library is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Library General Public License for more details.
;;;
;;; You should have received a copy of the GNU Library General Public
;;; License along with this library; if not, write to the
;;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;;; Boston, MA  02111-1307  USA.

;;; The CLIM pane used for displaying Climacs objects

(in-package :climacs-pane)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Tabify

(defvar *use-tabs-for-indentation* nil
  "If non-NIL, use tabs when indenting lines. Otherwise, use spaces.")

(defgeneric space-width (tabify))
(defgeneric tab-width (tabify))
(defgeneric tab-space-count (tabify))

(defclass tabify-mixin ()
  ((space-width :initform nil :reader space-width)
   (tab-width :initform nil :reader tab-width)))

(defmethod tab-space-count ((tabify t))
  1)

(defmethod tab-space-count ((tabify tabify-mixin))
  (round (tab-width tabify) (space-width tabify)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Undo

(defclass undo-mixin ()
  ((tree :initform (make-instance 'standard-undo-tree) :reader undo-tree)
   (undo-accumulate :initform '() :accessor undo-accumulate)
   (performing-undo :initform nil :accessor performing-undo)))

(defclass climacs-undo-record (standard-undo-record)
  ((buffer :initarg :buffer)))

(defclass simple-undo-record (climacs-undo-record)
  ((offset :initarg :offset)))

(defclass insert-record (simple-undo-record)
  ((objects :initarg :objects)))

(defclass delete-record (simple-undo-record)
  ((length :initarg :length)))

(defclass compound-record (climacs-undo-record)
  ((records :initform '() :initarg :records)))

(defmethod print-object  ((object delete-record) stream)
  (with-slots (offset length) object
     (format stream "[offset: ~a length: ~a]" offset length)))

(defmethod print-object  ((object insert-record) stream)
  (with-slots (offset objects) object
     (format stream "[offset: ~a objects: ~a]" offset objects)))

(defmethod print-object  ((object compound-record) stream)
  (with-slots (records) object
     (format stream "[records: ~a]" records)))

(defmethod insert-buffer-object :before ((buffer undo-mixin) offset object)
  (declare (ignore object))
  (unless (performing-undo buffer)
    (push (make-instance 'delete-record
	     :buffer buffer :offset offset :length 1)
	  (undo-accumulate buffer))))

(defmethod insert-buffer-sequence :before ((buffer undo-mixin) offset sequence)
  (unless (performing-undo buffer)
    (push (make-instance 'delete-record
	     :buffer buffer :offset offset :length (length sequence))
	  (undo-accumulate buffer))))

(defmethod delete-buffer-range :before ((buffer undo-mixin) offset n)
  (unless (performing-undo buffer)
    (push (make-instance 'insert-record
	     :buffer buffer :offset offset
	     :objects (buffer-sequence buffer offset (+ offset n)))
	  (undo-accumulate buffer))))

(defmacro with-undo ((buffer) &body body)
  (let ((buffer-var (gensym)))
    `(let ((,buffer-var ,buffer))
       (setf (undo-accumulate ,buffer-var) '())
       ,@body
       (cond ((null (undo-accumulate ,buffer-var)) nil)
	     ((null (cdr (undo-accumulate ,buffer-var)))
	      (add-undo (car (undo-accumulate ,buffer-var))
			(undo-tree ,buffer-var)))
	     (t
	      (add-undo (make-instance 'compound-record
				       :buffer ,buffer-var
				       :records (undo-accumulate ,buffer-var))
			(undo-tree ,buffer-var)))))))

(defmethod flip-undo-record :around ((record climacs-undo-record))
  (with-slots (buffer) record
     (let ((performing-undo (performing-undo buffer)))
       (setf (performing-undo buffer) t)
       (unwind-protect (call-next-method)
	 (setf (performing-undo buffer) performing-undo)))))

(defmethod flip-undo-record ((record insert-record))
  (with-slots (buffer offset objects) record
     (change-class record 'delete-record
		   :length (length objects))
     (insert-buffer-sequence buffer offset objects)))

(defmethod flip-undo-record ((record delete-record))
  (with-slots (buffer offset length) record
     (change-class record 'insert-record
		   :objects (buffer-sequence buffer offset (+ offset length)))
     (delete-buffer-range buffer offset length)))

(defmethod flip-undo-record ((record compound-record))
  (with-slots (records) record
     (mapc #'flip-undo-record records)
     (setf records (nreverse records))))

;;; undo-mixin delegation (here because of the package)

(defmethod undo-tree ((buffer delegating-buffer))
  (undo-tree (implementation buffer)))

(defmethod undo-accumulate ((buffer delegating-buffer))
  (undo-accumulate (implementation buffer)))

(defmethod (setf undo-accumulate) (object (buffer delegating-buffer))
  (setf (undo-accumulate (implementation buffer)) object))

(defmethod performing-undo ((buffer delegating-buffer))
  (performing-undo (implementation buffer)))

(defmethod (setf performing-undo) (object (buffer delegating-buffer))
  (setf (performing-undo (implementation buffer)) object))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Isearch

(defclass isearch-state ()
  ((search-string :initarg :search-string :accessor search-string)
   (search-mark :initarg :search-mark :accessor search-mark)
   (search-forward-p :initarg :search-forward-p :accessor search-forward-p)
   (search-success-p :initarg :search-success-p :accessor search-success-p)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Query replace

(defclass query-replace-state ()
  ((string1 :initarg :string1 :accessor string1)
   (string2 :initarg :string2 :accessor string2)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Readonly

(defclass read-only-mixin ()
     ((read-only-p :initform nil :accessor read-only-p)))

(define-condition buffer-read-only (simple-error)
  ((buffer :reader condition-buffer :initarg :buffer))
  (:report (lambda (condition stream)
	     (format stream "Attempt to change read only buffer: ~a"
		     (condition-buffer condition))))
  (:documentation "This condition is signalled whenever an attempt
is made to alter a buffer which has been set read only."))

(defmethod insert-buffer-object ((buffer read-only-mixin) offset object)
  (if (read-only-p buffer)
      (error 'buffer-read-only :buffer buffer)
      (call-next-method)))

(defmethod insert-buffer-sequence ((buffer read-only-mixin) offset sequence)
  (if (read-only-p buffer)
      (error 'buffer-read-only :buffer buffer)
      (call-next-method)))

(defmethod delete-buffer-range ((buffer read-only-mixin) offset n)
  (if (read-only-p buffer)
      (error 'buffer-read-only :buffer buffer)
      (call-next-method)))

(defmethod (setf buffer-object) (object (buffer read-only-mixin) offset)
  (if (read-only-p buffer)
      (error 'buffer-read-only :buffer buffer)
      (call-next-method)))

(defmethod read-only-p ((buffer delegating-buffer))
  (read-only-p (implementation buffer)))

(defmethod (setf read-only-p) (flag (buffer delegating-buffer))
  (setf (read-only-p (implementation buffer)) flag))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; View

(defclass climacs-textual-view (textual-view tabify-mixin)
  ())

(defparameter +climacs-textual-view+ (make-instance 'climacs-textual-view))

(defclass file-mixin ()
  ((filepath :initform nil :accessor filepath)
   (file-saved-p :initform nil :accessor file-saved-p)
   (file-write-time :initform nil :accessor file-write-time)))

;(defgeneric indent-tabs-mode (climacs-buffer))

(defclass extended-standard-buffer (read-only-mixin standard-buffer undo-mixin abbrev-mixin) ()
  (:documentation "Extensions accessible via marks."))

(defclass extended-binseq2-buffer (read-only-mixin binseq2-buffer p-undo-mixin abbrev-mixin) ()
  (:documentation "Extensions accessible via marks."))

(defclass climacs-buffer (delegating-buffer file-mixin name-mixin)
  ((needs-saving :initform nil :accessor needs-saving)
   (syntax :accessor syntax)
   (point :initform nil :initarg :point :accessor point)
   (indent-tabs-mode :initarg indent-tabs-mode
                     :initform *use-tabs-for-indentation*
                     :accessor indent-tabs-mode))
  (:default-initargs
   :name "*scratch*"
   :implementation (make-instance 'extended-standard-buffer)))

(defmethod initialize-instance :after ((buffer climacs-buffer) &rest args)
  (declare (ignore args))
  (with-slots (syntax point) buffer
     (setf syntax (make-instance
		   'basic-syntax :buffer (implementation buffer))
	   point (clone-mark (low-mark buffer) :right))))

(defmethod (setf syntax) :after (syntax (buffer climacs-buffer))
  (setf (offset (low-mark buffer)) 0
        (offset (high-mark buffer)) (size buffer)))

(defclass climacs-pane (application-pane)
  ((buffer :initform (make-instance 'climacs-buffer) :accessor buffer)
   (point :initform nil :initarg :point :accessor point)
   (mark :initform nil :initarg :mark :accessor mark)
   (top :reader top)
   (bot :reader bot)
   (scan :reader scan)
   (cursor-x :initform 2)
   (cursor-y :initform 2)
   (space-width :initform nil)
   (tab-width :initform nil)
   (auto-fill-mode :initform nil :accessor auto-fill-mode)
   (auto-fill-column :initform 70 :accessor auto-fill-column)
   (isearch-mode :initform nil :accessor isearch-mode)
   (isearch-states :initform '() :accessor isearch-states)
   (isearch-previous-string :initform nil :accessor isearch-previous-string)
   (query-replace-mode :initform nil :accessor query-replace-mode)
   (query-replace-state :initform nil :accessor query-replace-state)
   (region-visible-p :initform nil :accessor region-visible-p)
   (full-redisplay-p :initform nil :accessor full-redisplay-p)
   (cache :initform (let ((cache (make-instance 'standard-flexichain)))
		      (insert* cache 0 nil)
		      cache)))
  (:default-initargs
   :default-view +climacs-textual-view+))

(defgeneric clear-cache (pane)
  (:documentation "Clear the cache for `pane.'"))

(defmethod clear-cache ((pane climacs-pane))
  (with-slots (cache) pane
    (setf cache (let ((cache (make-instance 'standard-flexichain)))
                  (insert* cache 0 nil)
                  cache))))

(defmethod tab-width ((pane climacs-pane))
  (tab-width (stream-default-view pane)))

(defmethod space-width ((pane climacs-pane))
  (space-width (stream-default-view pane)))

(defmethod initialize-instance :after ((pane climacs-pane) &rest args)
  (declare (ignore args))
  (with-slots (buffer point mark) pane
     (setf point (clone-mark (point buffer)))
     (when (null point)
       (setf point (clone-mark (low-mark buffer) :right)))
     (when (null mark)
       (setf mark (clone-mark (low-mark buffer) :right))))
  (with-slots (buffer top bot scan) pane
     (setf top (clone-mark (low-mark buffer) :left)
	   bot (clone-mark (high-mark buffer) :right)))
  #-(and)
  (with-slots (space-width tab-width) (stream-default-view pane)
     (let* ((medium (sheet-medium pane))
	    (style (medium-text-style medium)))
       (setf space-width (text-style-width style medium)
	     tab-width (* 8 space-width)))))

(defmethod note-sheet-grafted :around ((pane climacs-pane))
  (call-next-method)
  (with-slots (space-width tab-width) (stream-default-view pane)
     (let ((medium (sheet-medium pane)))
       (setf (medium-text-style medium) (medium-default-text-style medium))
       (let ((style (medium-text-style medium)))
	 (setf space-width (text-style-width style medium)
	       tab-width (* 8 space-width))))))


(defmethod (setf buffer) :after (buffer (pane climacs-pane))
  (with-slots (point mark top bot) pane
       (setf point (clone-mark (point buffer))
	     mark (clone-mark (low-mark buffer) :right)
	     top (clone-mark (low-mark buffer) :left)
	     bot (clone-mark (high-mark buffer) :right))))

(define-presentation-type url ()
  :inherit-from 'string)

(defgeneric present-contents (contents pane))

(defmethod present-contents (contents pane)
  (unless (null contents)
    (present contents
	     (if (and (>= (length contents) 7) (string= (subseq contents 0 7) "http://"))
		 'url
		 'string)
	     :stream pane)))

(defgeneric display-line (pane line offset syntax view))

(defmethod display-line (pane line offset (syntax basic-syntax) (view textual-view))
  (declare (ignore offset))
  (let ((saved-index nil)
	(id 0))
    (flet ((output-word (index)
	     (unless (null saved-index)
	       (let ((contents (coerce (subseq line saved-index index) 'string)))
		 (updating-output (pane :unique-id (incf id)
					:cache-value contents
					:cache-test #'string=)
		   (present-contents contents pane)))
	       (setf saved-index nil))))
      (with-slots (bot scan cursor-x cursor-y) pane
	 (loop with space-width = (space-width pane)
	       with tab-width = (tab-width pane)
	       for index from 0
	       for obj across line
	       when (mark= scan (point pane))
		 do (multiple-value-bind (x y) (stream-cursor-position pane)
		      (setf cursor-x (+ x (if (null saved-index)
					      0
					      (* space-width (- index saved-index))))
			    cursor-y y))
	       do (cond ((eql obj #\Space)
			 (output-word index)
			 (stream-increment-cursor-position pane space-width 0))
			((eql obj #\Tab)
			 (output-word index)
			 (let ((x (stream-cursor-position pane)))
			   (stream-increment-cursor-position
			    pane (- tab-width (mod x tab-width)) 0)))
			((constituentp obj)
			 (when (null saved-index)
			   (setf saved-index index)))
			((characterp obj)
			 (output-word index)
			 (updating-output (pane :unique-id (incf id)
						:cache-value obj)
			   (present obj 'character :stream pane)))
			(t
			 (output-word index)
			 (updating-output (pane :unique-id (incf id)
						:cache-value obj
						:cache-test #'eq)
			   (present obj 'character :stream pane))))
		  (incf scan)
	       finally (output-word index)
		       (when (mark= scan (point pane))
			 (multiple-value-bind (x y) (stream-cursor-position pane)
			   (setf cursor-x x
				 cursor-y y)))
		       (terpri pane)
		       (incf scan))))))

(defgeneric fill-cache (pane)
  (:documentation "fill nil cache entries from the buffer"))

(defmethod fill-cache (pane)
  (with-slots (top bot cache) pane
     (let ((mark1 (clone-mark top))
	   (mark2 (clone-mark top)))
       (loop for line from 0 below (nb-elements cache)
	     do (beginning-of-line mark1)
		(end-of-line mark2)
	     when (null (element* cache line))
	       do (setf (element* cache line) (region-to-sequence mark1 mark2))
	     unless (end-of-buffer-p mark2)
	       do (setf (offset mark1) (1+ (offset mark2))
			(offset mark2) (offset mark1))))))

(defun nb-lines-in-pane (pane)
  (let* ((medium (sheet-medium pane))
	 (style (medium-text-style medium))
	 (height (text-style-height style medium)))
    (multiple-value-bind (x y w h) (bounding-rectangle* pane)
      (declare (ignore x y w))
      (max 1 (floor h (+ height (stream-vertical-spacing pane)))))))

;;; make the region on display fit the size of the pane as closely as
;;; possible by adjusting bot leaving top intact.  Also make the cache
;;; size fit the size of the region on display.
(defun adjust-cache-size-and-bot (pane)
  (let ((nb-lines-in-pane (nb-lines-in-pane pane)))
    (with-slots (top bot cache) pane
       (setf (offset bot) (offset top))
       (end-of-line bot)
       (loop until (end-of-buffer-p bot)
	     repeat (1- nb-lines-in-pane)
	     do (forward-object bot)
		(end-of-line bot))
       (let ((nb-lines-on-display (1+ (number-of-lines-in-region top bot))))
	 (loop repeat (- (nb-elements cache) nb-lines-on-display)
	       do (pop-end cache))
	 (loop repeat (- nb-lines-on-display (nb-elements cache))
	       do (push-end cache nil))))))

;;; put all-nil entries in the cache
(defun empty-cache (cache)
  (loop for i from 0 below (nb-elements cache)
	do (setf (element* cache i) nil)))	     

;;; empty the cache and try to put point close to the middle
;;; of the pane by moving top half a pane-size up.
(defun reposition-window (pane)
  (let ((nb-lines-in-pane (nb-lines-in-pane pane)))
    (with-slots (top cache) pane
       (empty-cache cache)
       (setf (offset top) (offset (point pane)))
       (loop do (beginning-of-line top)
	     repeat (floor nb-lines-in-pane 2)
	     until (beginning-of-buffer-p top)
	     do (decf (offset top))
		(beginning-of-line top)))))

;;; Make the cache reflect the contents of the buffer starting at top,
;;; trying to preserve contents as much as possible, and inserting a
;;; nil entry where buffer contents is unknonwn.  The size of the
;;; cache at the end may be smaller than, equal to, or greater than
;;; the number of lines in the pane.
(defun adjust-cache (pane)
  (let* ((buffer (buffer pane))
	 (high-mark (high-mark buffer))
	 (low-mark (low-mark buffer))
	 (nb-lines-in-pane (nb-lines-in-pane pane)))
    (with-slots (top bot cache) pane
       (beginning-of-line top)
       (end-of-line bot)
       (if (or (mark< (point pane) top)
	       (>= (number-of-lines-in-region top (point pane)) nb-lines-in-pane)
	       (and (mark< low-mark top)
		    (>= (number-of-lines-in-region top high-mark) (nb-elements cache))))
	   (reposition-window pane)
	   (when (mark>= high-mark low-mark)
	     (let* ((n1 (number-of-lines-in-region top low-mark))
		    (n2 (1+ (number-of-lines-in-region low-mark high-mark)))
		    (n3 (number-of-lines-in-region high-mark bot))
		    (diff (- (+ n1 n2 n3) (nb-elements cache))))
	       (cond ((>= (+ n1 n2 n3) (+ (nb-elements cache) 20))
		      (setf (offset bot) (offset top))
		      (end-of-line bot)
		      (loop for i from n1 below (nb-elements cache)
			    do (setf (element* cache i) nil)))
		     ((>= diff 0)
		      (loop repeat diff do (insert* cache n1 nil))
		      (loop for i from (+ n1 diff) below (+ n1 n2)
			    do (setf (element* cache i) nil)))
		     (t
		      (loop repeat (- diff) do (delete* cache n1))
		      (loop for i from n1 below (+ n1 n2)
			    do (setf (element* cache i) nil)))))))))
  (adjust-cache-size-and-bot pane))

(defun page-down (pane)
  (adjust-cache pane)
  (with-slots (top bot cache) pane
     (when (mark> (size (buffer bot)) bot)
       (empty-cache cache)
       (setf (offset top) (offset bot))
       (beginning-of-line top)
       (setf (offset (point pane)) (offset top)))))

(defun page-up (pane)
  (adjust-cache pane)
  (with-slots (top bot cache) pane
     (when (> (offset top) 0)
       (let ((nb-lines-in-region (number-of-lines-in-region top bot)))
	 (setf (offset bot) (offset top))
	 (end-of-line bot)
	 (loop repeat  nb-lines-in-region
	       while (> (offset top) 0)
	       do (decf (offset top))
		  (beginning-of-line top))
	 (setf (offset (point pane)) (offset top))
	 (adjust-cache pane)
	 (setf (offset (point pane)) (offset bot))
	 (beginning-of-line (point pane))
	 (empty-cache cache)))))

(defun display-cache (pane)
  (with-slots (top bot scan cache cursor-x cursor-y) pane
     (loop with start-offset = (offset top)
	   for id from 0 below (nb-elements cache)
	   do (setf scan start-offset)
	      (updating-output
		  (pane :unique-id (element* cache id)
			:cache-value (if (<= start-offset
					     (offset (point pane))
					     (+ start-offset (length (element* cache id))))
					 (cons nil nil)
					 (element* cache id))
			:cache-test #'eq)
		(display-line pane (element* cache id) start-offset
			      (syntax (buffer pane)) (stream-default-view pane)))
	      (incf start-offset (1+ (length (element* cache id)))))
     (when (mark= scan (point pane))
       (multiple-value-bind (x y) (stream-cursor-position pane)
	 (setf cursor-x x
	       cursor-y y)))))  

(defgeneric fix-pane-viewport (pane))

(defmethod fix-pane-viewport ((pane climacs-pane))
  (let* ((v (window-viewport pane))
	(x (rectangle-width v))
	(y (rectangle-height v)))
    (resize-sheet pane x y)
    (setf (window-viewport-position pane) (values 0 0))))


(defmethod redisplay-pane-with-syntax ((pane climacs-pane) (syntax basic-syntax) current-p)
  (display-cache pane)
  (when (region-visible-p pane) (display-region pane syntax))
  (display-cursor pane syntax current-p))

(defgeneric redisplay-pane (pane current-p))

(defmethod redisplay-pane ((pane climacs-pane) current-p)
  (if (full-redisplay-p pane)
      (progn (reposition-window pane)
	     (adjust-cache-size-and-bot pane)
	     (setf (full-redisplay-p pane) nil))
      (adjust-cache pane))
  (fill-cache pane)
  (fix-pane-viewport pane)
  (update-syntax-for-display (buffer pane) (syntax (buffer pane)) (top pane) (bot pane))
  (redisplay-pane-with-syntax pane (syntax (buffer pane)) current-p))


(defgeneric full-redisplay (pane))

(defmethod full-redisplay ((pane climacs-pane))
  (setf (full-redisplay-p pane) t))

(defgeneric display-cursor (pane syntax current-p))

(defmethod display-cursor ((pane climacs-pane) (syntax basic-syntax) current-p)
  (let ((point (point pane)))
    (multiple-value-bind (cursor-x cursor-y line-height)
	(offset-to-screen-position (offset point) pane)
      (updating-output (pane :unique-id -1)
	(draw-rectangle* pane
			 (1- cursor-x) cursor-y
			 (+ cursor-x 2) (+ cursor-y line-height)
			 :ink (if current-p +red+ +blue+))))))

(defgeneric display-region (pane syntax))

(defmethod display-region ((pane climacs-pane) (syntax basic-syntax))
  (multiple-value-bind (cursor-x cursor-y line-height)
      (offset-to-screen-position (offset (point pane)) pane)
    (multiple-value-bind (mark-x mark-y)
	(offset-to-screen-position (offset (mark pane)) pane)
      (cond
	;; mark is above the top of the screen
	((and (null mark-y) (null mark-x))
	 (updating-output (pane :unique-id -3)
	   (draw-rectangle* pane
			    0 0
			    (stream-text-margin pane) cursor-y
			    :ink (compose-in +green+
					     (make-opacity .1)))
	   (draw-rectangle* pane
			    0 cursor-y 
			    cursor-x (+ cursor-y line-height)
			    :ink (compose-in +green+
					     (make-opacity .1)))))
	;; mark is below the bottom of the screen
	((and (null mark-y) mark-x)
	 (updating-output (pane :unique-id -3)
	   (draw-rectangle* pane
			    0 (+ cursor-y line-height)
			    (stream-text-margin pane) (bounding-rectangle-height
						       (window-viewport pane))
			    :ink (compose-in +green+
					     (make-opacity .1)))
	   (draw-rectangle* pane
			    cursor-x cursor-y
			    (stream-text-margin pane) (+ cursor-y line-height)
			    :ink (compose-in +green+
					     (make-opacity .1)))))
	;; mark is at point
	((and (= mark-x cursor-x) (= mark-y cursor-y))
	 nil)
	;; mark and point are on the same line
	((= mark-y cursor-y)
	 (updating-output (pane :unique-id -3)
	   (draw-rectangle* pane
			    mark-x mark-y
			    cursor-x (+ cursor-y line-height)
			    :ink (compose-in +green+
					     (make-opacity .1)))))
	;; mark and point are both visible, mark above point
	((< mark-y cursor-y)
	 (updating-output (pane :unique-id -3)
	   (draw-rectangle* pane
			    mark-x mark-y
			    (stream-text-margin pane) (+ mark-y line-height)
			    :ink (compose-in +green+
					     (make-opacity .1)))
	   (draw-rectangle* pane
			    0 cursor-y
			    cursor-x (+ cursor-y line-height)
			    :ink (compose-in +green+
					     (make-opacity .1)))
	   (draw-rectangle* pane
			    0 (+ mark-y line-height)
			    (stream-text-margin pane) cursor-y
			    :ink (compose-in +green+
					     (make-opacity .1)))))
	;; mark and point are both visible, point above mark
	(t
	 (updating-output (pane :unique-id -3)
	   (draw-rectangle* pane
			    cursor-x cursor-y
			    (stream-text-margin pane) (+ cursor-y line-height)
			    :ink (compose-in +green+
					     (make-opacity .1)))
	   (draw-rectangle* pane
			    0 mark-y
			    mark-x (+ mark-y line-height)
			    :ink (compose-in +green+
					     (make-opacity .1)))
	   (draw-rectangle* pane
			    0 (+ cursor-y line-height)
			    (stream-text-margin pane) mark-y
			    :ink (compose-in +green+
					     (make-opacity .1)))))))))

(defun offset-to-screen-position (offset pane)
  "Returns the position of offset as a screen position.
Returns X Y LINE-HEIGHT CHAR-WIDTH as values if offset is on the screen,
NIL if offset is before the beginning of the screen,
and T if offset is after the end of the screen."
  (with-slots (top bot) pane
     (cond
       ((< offset (offset top)) nil)
       ((< (offset bot) offset) t)
       (t
	(let* ((line (number-of-lines-in-region top offset))
	       (style (medium-text-style pane))
	       (style-width (text-style-width style pane))
	       (ascent (text-style-ascent style pane))
	       (descent (text-style-descent style pane))
	       (height (+ ascent descent))
	       (y (+ (* line (+ height (stream-vertical-spacing pane)))))
	       (column 
		(buffer-display-column
		 (buffer pane) offset
		 (round (tab-width pane) (space-width pane))))
	       (x (* column style-width)))
	  (values x y height style-width))))))