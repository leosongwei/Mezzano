(in-package :mezzanine.supervisor)

;;; FIXME: Should not be here.
;;; >>>>>>

(defun sys.int::current-thread ()
  (sys.int::%%assemble-value (sys.int::msr sys.int::+msr-ia32-gs-base+) 0))

(defun integerp (object)
  (sys.int::fixnump object))

(defun sys.int::%coerce-to-callable (object)
  (etypecase object
    (function object)
    (symbol
     (sys.int::%array-like-ref-t
      (sys.int::%array-like-ref-t object sys.c::+symbol-function+)
      sys.int::+fref-function+))))

;; Hardcoded string accessor, the support stuff for arrays doesn't function at this point.
(defun char (string index)
  (assert (sys.int::character-array-p string) (string))
  (let ((data (sys.int::%array-like-ref-t string 0)))
    (assert (and (<= 0 index)
                 (< index (sys.int::%object-header-data data)))
            (string index))
    (code-char
     (case (sys.int::%object-tag data)
       (#.sys.int::+object-tag-array-unsigned-byte-8+
        (sys.int::%array-like-ref-unsigned-byte-8 data index))
       (#.sys.int::+object-tag-array-unsigned-byte-16+
        (sys.int::%array-like-ref-unsigned-byte-16 data index))
       (#.sys.int::+object-tag-array-unsigned-byte-32+
        (sys.int::%array-like-ref-unsigned-byte-32 data index))
       (t 0)))))

(defun length (sequence)
  (if (sys.int::character-array-p sequence)
      (sys.int::%array-like-ref-t sequence 3)
      nil))

(defun code-char (code)
  (sys.int::%%assemble-value (ash code 4) sys.int::+tag-character+))

(defun char-code (character)
  (logand (ash (sys.int::lisp-object-address character) -4) #x1FFFFF))

(declaim (special sys.int::*newspace* sys.int::*newspace-offset*))

(defvar *allocator-lock*)

(defun %allocate-object (tag data size area)
  (declare (ignore area))
  (let ((words (1+ size)))
    (when (oddp words)
      (incf words))
    (with-spinlock (*allocator-lock*)
      ;; Assume we have enough memory to do the allocation...
      ;; And that the memory is already zero initialized.
      (let ((addr (+ sys.int::*newspace* (ash sys.int::*newspace-offset* 3))))
        (incf sys.int::*newspace-offset* words)
        ;; Write array header.
        (setf (sys.int::memref-unsigned-byte-64 addr 0)
              (logior (ash tag sys.int::+array-type-shift+)
                      (ash data sys.int::+array-length-shift+)))
        (sys.int::%%assemble-value addr sys.int::+tag-object+)))))

(defun sys.int::make-simple-vector (size &optional area)
  (%allocate-object sys.int::+object-tag-array-t+ size size area))

(defun sys.int::%make-struct (size &optional area)
  (%allocate-object sys.int::+object-tag-structure-object+ size size area))

(defun sys.int::cons-in-area (car cdr &optional area)
  (declare (ignore area))
  (with-spinlock (*allocator-lock*)
    ;; Assume we have enough memory to do the allocation...
    (let ((addr (+ sys.int::*newspace* (ash sys.int::*newspace-offset* 3))))
      (incf sys.int::*newspace-offset* 2)
      ;; Set car/cdr.
      (setf (sys.int::memref-t addr 0) car
            (sys.int::memref-t addr 1) cdr)
      (sys.int::%%assemble-value addr sys.int::+tag-cons+))))

;; TODO.
(defun sleep (seconds)
  nil)

(sys.int::define-lap-function sys.int::%%coerce-fixnum-to-float ()
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:sar64 :rax #.sys.int::+n-fixnum-bits+)
  (sys.lap-x86:cvtsi2ss64 :xmm0 :rax)
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.sys.int::+tag-single-float+))
  (sys.lap-x86:mov32 :ecx #.(ash 1 sys.int::+n-fixnum-bits+))
  (sys.lap-x86:ret))

(sys.int::define-lap-function sys.int::%%float-+ ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Add.
  (sys.lap-x86:addss :xmm0 :xmm1)
  ;; Box.
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.sys.int::+tag-single-float+))
  (sys.lap-x86:mov32 :ecx #.(ash 1 sys.int::+n-fixnum-bits+))
  (sys.lap-x86:ret))

(sys.int::define-lap-function sys.int::%%float-- ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Add.
  (sys.lap-x86:subss :xmm0 :xmm1)
  ;; Box.
  (sys.lap-x86:movd :eax :xmm0)
  (sys.lap-x86:shl64 :rax 32)
  (sys.lap-x86:lea64 :r8 (:rax #.sys.int::+tag-single-float+))
  (sys.lap-x86:mov32 :ecx #.(ash 1 sys.int::+n-fixnum-bits+))
  (sys.lap-x86:ret))

(sys.int::define-lap-function sys.int::%%float-< ()
  ;; Unbox the floats.
  (sys.lap-x86:mov64 :rax :r8)
  (sys.lap-x86:shr64 :rax 32)
  (sys.lap-x86:mov64 :rdx :r9)
  (sys.lap-x86:shr64 :rdx 32)
  ;; Load into XMM registers.
  (sys.lap-x86:movd :xmm0 :eax)
  (sys.lap-x86:movd :xmm1 :edx)
  ;; Compare.
  (sys.lap-x86:ucomiss :xmm0 :xmm1)
  (sys.lap-x86:mov64 :r8 nil)
  (sys.lap-x86:mov64 :r9 t)
  (sys.lap-x86:cmov64b :r8 :r9)
  (sys.lap-x86:mov32 :ecx #.(ash 1 sys.int::+n-fixnum-bits+))
  (sys.lap-x86:ret))

(defun sys.int::generic-+ (x y)
  (cond ((or (floatp x)
             (floatp y))
         (when (sys.int::fixnump x)
           (setf x (sys.int::%%coerce-fixnum-to-float x)))
         (when (sys.int::fixnump y)
           (setf y (sys.int::%%coerce-fixnum-to-float y)))
         (sys.int::%%float-+ x y))
        (t (error "Unsupported argument combination."))))

(defun sys.int::generic-- (x y)
  (cond ((or (floatp x)
             (floatp y))
         (when (sys.int::fixnump x)
           (setf x (sys.int::%%coerce-fixnum-to-float x)))
         (when (sys.int::fixnump y)
           (setf y (sys.int::%%coerce-fixnum-to-float y)))
         (sys.int::%%float-- x y))
        (t (error "Unsupported argument combination."))))

(defun sys.int::generic-< (x y)
  (cond ((or (floatp x)
             (floatp y))
         (when (sys.int::fixnump x)
           (setf x (sys.int::%%coerce-fixnum-to-float x)))
         (when (sys.int::fixnump y)
           (setf y (sys.int::%%coerce-fixnum-to-float y)))
         (sys.int::%%float-< x y))
        (t (error "Unsupported argument combination."))))

(defun sys.int::generic-> (x y)
  (sys.int::generic-< y x))

(defun sys.int::generic-<= (x y)
  (not (sys.int::generic-< y x)))

(defun sys.int::generic->= (x y)
  (not (sys.int::generic-< x y)))

;;; <<<<<<

(defun initialize-initial-thread ()
  (let* ((sg (sys.int::current-thread))
         (bs-base (sys.int::%array-like-ref-unsigned-byte-64 sg sys.int::+stack-group-offset-binding-stack-base+))
         (bs-size (sys.int::%array-like-ref-unsigned-byte-64 sg sys.int::+stack-group-offset-binding-stack-size+)))
    ;; Clear binding stack.
    (dotimes (i (truncate bs-size 8))
      (setf (sys.int::memref-unsigned-byte-64 bs-base i) 0))
    ;; Set the binding stack pointer.
    (setf (sys.int::%array-like-ref-unsigned-byte-64 sg sys.int::+stack-group-offset-binding-stack-pointer+)
          (+ bs-base bs-size))
    ;; Reset the TLS binding slots.
    (dotimes (i sys.int::+stack-group-tls-slots-size+)
      (setf (sys.int::%array-like-ref-t sg (+ sys.int::+stack-group-offset-tls-slots+ i))
            (sys.int::%unbound-tls-slot)))))

(defun sys.int::bootloader-entry-point ()
  ;; The bootloader current does not properly initialize the
  ;; initial thread, do that now.
  (initialize-initial-thread)
  (setf *allocator-lock* :unlocked)
  (initialize-interrupts)
  (initialize-i8259)
  (sys.int::%sti)
  (initialize-debug-serial #x3F8 4)
  (debug-write-line "Hello, Debug World!")
  (initialize-ata)
  (ata-read (car *ata-devices*) 0 32 (logior (ash -1 48) #x800000001000))
  (loop))
