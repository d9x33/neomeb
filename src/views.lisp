(in-package #:nmebious)

(add-template-directory (asdf:system-relative-pathname 'nmebious "templates/"))

(defparameter +mebious.html+ (compile-template* "mebious.html"))
(defparameter +404.html+ (compile-template* "404.html"))
(defparameter +about.html+ (compile-template* "about.html"))
(defparameter +preferences.html+ (compile-template* "preferences.html"))

;; Text stuff
(defun get-font ()
  (let* ((fonts '("Times New Roman" "Times" "serif" "Arial"
                  "Helvetica" "sans-serif" "Georgia" "Courier New"
                  "Courier" "monospace")))
    (nth (random (length fonts)) fonts)))

(defun gen-color (hue &optional (sat (random-in-range 0 100)))
  (let* ((lum (random-in-range 20 100)))
    (format nil "hsl(~A, ~A%, ~A%)" hue sat lum)))

(defun hex-to-hsl (hex)
  (let* ((r (/ (parse-integer (subseq hex 1 3) :radix 16) 255))
         (g (/ (parse-integer (subseq hex 3 5) :radix 16) 255))
         (b (/ (parse-integer (subseq hex 5 7) :radix 16) 255))
         (max (max r g b))
         (min (min r g b))
         (l (/ (+ max min) 2)))
    (if (eql max min)
        (list 0 0 (* 100 l))
        (let* ((d (- max min))
               (s (if (> l 0.5)
                      (- 2 max min)
                      (/ d (+ max min))))
               (h (/ (cond ((eql max r)
                            (+ (/ (- g b)
                                  d)
                               (if (< g b)
                                   6 0)))
                           ((eql max g)
                            (+ (/ (- b r)
                                  d)
                               2))
                           ((eql max b)
                            (+ (/ (- r g)
                                  d)
                               4)))
                     6)))
          (list (round (* 360 h)) (round (* s 100)) (round (* 100 l)))))))

(defun text-style (board)
  (let* ((color (let* ((board-color-hex (color-for-board board)))
                  (if board-color-hex
                      (let* ((board-color-hsl (hex-to-hsl board-color-hex)))
                        ;; if achromatic
                        (if (and (eql 0 (first board-color-hsl))
                                 (eql 0 (second board-color-hsl)))
                            (gen-color 0 0)
                            (gen-color (first board-color-hsl))))
                      (gen-color 120))))
         (font-size (random-in-range 0.8 2.0))
         (left (random-in-range 0.1 40.0))
         (font-family (get-font)))
    (format nil
            "color: ~A; font-family: ~A; font-size: ~Aem; left: ~A%"
            color font-family font-size left)))

(defun corrupt (text)
  (let* ((corruptions (pairlis '(#\a #\e #\i #\o #\u #\y #\s)
                               '((#\á #\ã #\à #\@)
                                 (#\è #\ë #\ê)
                                 (#\ï #\î #\1)
                                 (#\ø #\ò #\ô)
                                 (#\ü #\ù)
                                 (#\ÿ)
                                 (#\$)))))
    (map 'string #'(lambda (char)
                     (let* ((corruptions-for-character (cassoc char corruptions)))
                       (if (and corruptions-for-character
                                (eql (random 2)
                                     1))
                           (nth (random (length corruptions-for-character)) corruptions-for-character)
                           char)))
         text)))

(defun stylize-text-post (post)
  (acons :data (corrupt (cassoc :data post)) (acons :style (text-style (cassoc :board post)) post)))

;; File stuff
(defun file-style ()
  (let* ((z-index (- (random-in-range 1 10)))
         (left (random-in-range 0.1 50.0))
         (opacity (random-in-range 0.5 1.0))
         (top (random-in-range 7.0 50.0)))
    (format nil
            "z-index: ~A; left: ~A%; opacity: ~A; top: ~A%" z-index left opacity top)))

(defun stylize-file-post (post)
  (acons :style (file-style) post))

;; Rendering
(defun render-board (board &key error (page 0))
  (let* ((text-posts (select-posts *text-display-count* (* page *text-display-count*) :type "text" :board board))
         (file-posts (select-posts *file-display-count* (* page *file-display-count*) :type "file" :board board))
         (stylized-text-posts (map 'list #'stylize-text-post text-posts))
         (stylized-file-posts (map 'list #'stylize-file-post file-posts)))
    (render-template* +mebious.html+ nil
                      :text-posts stylized-text-posts
                      :file-posts stylized-file-posts
                      :active-board board
                      :single-board-p (single-board-p)
                      :user-prefs (parse-user-preferences)
                      :board-names (unless (single-board-p)
                                     (alist-keys *boards*))
                      :board-data (cassoc board *boards* :test #'string=)
                      :csrf-token (session-csrf-token)
                      :next-page (if (or
                                      (> (length text-posts) 0)
                                      (> (length file-posts) 0))
                                     (+ page 1)
                                     nil)
                      :prev-page (if
                                  (> page 0)
                                  (- page 1)
                                  nil)
                      :error error)))

(defun render-404 ()
  (render-template* +404.html+ nil))

(defun render-about-page ()
  (render-template* +about.html+ nil
                    :boards *boards*
                    :accepted-mime-types *accepted-mime-types*
                    :max-file-size (write-to-string  *max-file-size*)
                    :pagination-enabled-p *pagination-on-default-frontend-enabled-p*))

(defun render-preferences-page ()
  (let* ((user-prefs (parse-user-preferences))
         (render-prefs (map 'list
                            #'(lambda (pref)
                                (let* ((keyword-pref (car pref)))
                                  (car (acons keyword-pref (acons :current
                                                                  (cassoc (string-downcase (car pref)) user-prefs :test #'string=)
                                                                  (cassoc keyword-pref *web-user-preferences*))
                                              nil))))
                            *web-user-preferences*)))
    (render-template* +preferences.html+ nil
                      :preferences render-prefs)))
