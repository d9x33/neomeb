(in-package #:nmebious)

;; POST text via API
(defroute api-submit-text ("/api/submit/text" :method :post
                                              :decorators (@json @check-banned)) ()
  (with-fail-handler (api-submit-text :type 'api)
    (after-submit-text *success*)))

;; POST file via API
(defroute api-submit-file ("/api/submit/file" :method :post
                                              :decorators (@json @check-banned)) ()
  (with-fail-handler (api-submit-file :type 'api)
    (after-submit-file *success*)))

;; GET posts via API
(defroute get-posts ("/api/posts/:board" :method :get
                                         :decorators (@json))
    ((type :parameter-type 'string)
     (count :init-form 15 :parameter-type 'integer)
     (offset :init-form 0 :parameter-type 'integer))
  (with-fail-handler (get-posts :type 'api)
    (let* ((board (parse-board board))
           (ip-hash (hash-ip (real-remote-addr))))
      (after-get-request-validity-check (:count count
                                         :offset offset
                                         :type type
                                         :board board)
        (encode-json-alist-to-string (pairlis '(posts)
                                              (list (select-posts count
                                                                  offset
                                                                  :type type
                                                                  :board board))))))))

;; Server configuration in JSON format
(defroute config ("/api/config" :method :get
                                :decorators (@json)) ()
  (with-fail-handler (config)
    (encode-json-alist-to-string (pairlis '(boards accepted-mime-types post-get-limit max-file-size)
                                          (list  *boards* *accepted-mime-types* *post-get-limit* *max-file-size*)))))

;; RSS feed
(defroute rss-feed ("/rss/:board" :method :get
                                  :decorators (@rss))
    ((page :init-form 0 :parameter-type 'integer))
  (with-fail-handler (rss-feed :type 'web-view)
    (let* ((board (parse-board board)))
      (if (and board
               (single-board-p))
          (render-404)
          (after-get-request-validity-check (:board board
                                             :page page)
            (let* ((posts (select-posts 30 (* page 30) :board board))
                   (sorted-posts (sort posts
                                       #'sort-posts-by-id)))
              (with-output-to-string (s)
                (with-rss2 (s :encoding "utf-8")
                  (rss-channel-header "nmebious" *web-url*
                                      :description "monitoring the wired")
                  (dolist (item sorted-posts)
                    (let* ((data (cassoc :data item))
                           (id (cassoc :id item))
                           (board (cassoc :board item))
                           (date (cassoc :submission-date item)))
                      (rss-item nil
                                :guid id
                                :category (unless (single-board-p) board)
                                :description data
                                :pubDate date)))))))))))

;; POST file via the default frontend
(defroute web-submit-file ("/web-view/submit/file" :method :post
                                                   :decorators (@html @check-banned @check-frontend-enabled)) ()
  (with-fail-handler (web-submit-file :type 'web-view-submission)
    (require-session-csrf-token :post)
    (after-submit-file
      (redirect-back-to-board))))

;; POST text via the default frontend
(defroute web-submit-text ("/web-view/submit/text" :method :post
                                                   :decorators (@html @check-banned @check-frontend-enabled)) ()
  (with-fail-handler (web-submit-text :type 'web-view-submission)
    (require-session-csrf-token :post)
    (after-submit-text
      (redirect-back-to-board))))

;; View for a board
(defroute web-board ("/boards/:board" :method :get
                                      :decorators (@html @check-frontend-enabled))
     ((page :init-form 0 :parameter-type 'integer))
  (with-fail-handler (web-board :type 'web-view)
    (if (or (single-board-p)
            (and (not *pagination-on-default-frontend-enabled-p*)
                 (> page 0)))
        (render-404)
        (progn
          (start-session)
          (harden-session-cookie)
          (let* ((flash-message (session-value :flash-message)))
            (setf (session-value :flash-message) nil)
            (after-get-request-validity-check (:board board
                                               :page page)
              (setf (session-value :board) board)
              (render-board board :page page :error flash-message)))))))

;; About page (basic info on nmebious + configuration for this specific server and additional tips)
(defroute web-about ("/about" :method :get
                              :decorators (@html @check-frontend-enabled)) ()
  (with-fail-handler (web-about :type 'web-view)
    (render-about-page)))

;; Custom user-specific configuration for the front-end
(defroute web-user-preferences ("/preferences"
                                :decorators (@html @check-frontend-enabled)) ()
  (with-fail-handler (web-user-preferences :type 'web-view)
    (case (request-method*)
      (:get
       (render-preferences-page))
      (:post
       (let* ((preferences (alist-keys *web-user-preferences*))
              (post-params (post-parameters*))
              (new-preferences (url-encode-params (reduce #'(lambda (acc pref)
                                                              (acons (string-downcase pref)
                                                                     (if  (cassoc pref post-params :test #'string=)
                                                                          "on"
                                                                          "off")
                                                                     acc))
                                                          preferences
                                                          :initial-value '()))))
         (set-cookie "mebious_user"
                     :value new-preferences
                     :max-age 315360000
                     :path "/"
                     :secure t
                     :http-only t)
         (redirect "/preferences"))))))

(defroute web-root ("/" :method :get
                        :decorators (@html @check-frontend-enabled))
    ((page :init-form 0 :parameter-type 'integer))
  (with-fail-handler (web-root :type 'web-view)
    (if (single-board-p)
        (if (and (not *pagination-on-default-frontend-enabled-p*)
                 (> page 0))
            (render-404)
            (progn
              (start-session)
              (harden-session-cookie)
              (let* ((flash-message (session-value :flash-message)))
                (setf (session-value :flash-message) nil)
                (after-get-request-validity-check (:page page)
                  (setf (session-value :board) (caar *boards*))
                  (render-board (caar *boards*) :page page :error flash-message)))))
        (redirect (format nil "/boards/~A" (caar *boards*))))))
