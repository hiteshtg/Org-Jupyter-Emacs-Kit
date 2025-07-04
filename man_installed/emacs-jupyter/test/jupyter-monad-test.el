;;; jupyter-monad-test.el --- Test monadic I/O -*- lexical-binding: t -*-

;; Copyright (C) 2020-2024 Nathaniel Nicandro

;; Author: Nathaniel Nicandro <nathanielnicandro@gmail.com>
;; Created: 16 May 2020

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;;; Code:

(require 'jupyter-monads)

;; Kernel messages are property list representations of JSON encoded
;; strings.

;; A kernel client is a publisher of requests and subscriber of
;; kernel messages.

(ert-deftest jupyter-verify-monad-axioms ()
  :tags '(monad)
  (let ((f (lambda (n) (jupyter-return (/ n 0.5))))
        (g (lambda (n) (jupyter-return (* n 3))))
        (m (jupyter-return 9)))
    (should (equal
             (jupyter-run-with-state '()
               (jupyter-bind (jupyter-return 1) f))
             (jupyter-run-with-state '()
               (funcall f 1))))
    (should (equal (jupyter-run-with-state '()
                     (jupyter-bind m #'jupyter-return))
                   (jupyter-run-with-state '()
                     m)))
    (should (equal
             (jupyter-run-with-state '()
               (jupyter-bind
                   ;; Instead of applying a function, f, to a
                   ;; value, a, to get b, you bind a delayed value
                   ;; M a to f to get M b.  Binding unboxes M a
                   ;; into a and then applies f on a.
                   (jupyter-bind m f) g))
             (jupyter-run-with-state '()
               (jupyter-bind m
                 (lambda (x) (jupyter-bind (funcall f x) g))))))))

(ert-deftest jupyter-mlet* ()
  :tags '(monad)
  (should (equal (jupyter-mlet* ((a (jupyter-return 1))))
                 (jupyter-bind (jupyter-return 1)
                   (lambda (a) jupyter--return-nil))))
  (should (equal (jupyter-mlet* ((a (jupyter-return 1)))
                   a)
                 (jupyter-bind (jupyter-return 1)
                   (lambda (a) (progn a)))))
  (should (equal (jupyter-mlet* ((a (jupyter-return 2))
                                 (b (jupyter-return (* a 3))))
                   b)
                 (jupyter-bind (jupyter-return 2)
                   (lambda (a)
                     (jupyter-bind (jupyter-return (* a 3))
                       (lambda (b) (progn b))))))))

(ert-deftest jupyter-publisher/subscriber ()
  :tags '(monad)
  ;; Publisher/subscriber
  (ert-info ("Publisher/subscriber")
    (let* ((msgs '())
           (pub (jupyter-publisher))
           (sub (jupyter-subscriber
                  (lambda (n)
                    (if (> n 2) (jupyter-unsubscribe)
                      (push n msgs))))))
      (jupyter-run-with-io pub
        (jupyter-subscribe sub))
      (cl-loop
       for x in '(1 2 3)
       do (jupyter-run-with-io pub
            (jupyter-publish x)))
      (should (equal '(2 1) msgs))))
  (ert-info ("Subscriber errors")
    (ert-info ("`jupyter-subscribed-subscriber' error")
      (let* ((n 1)
             (sub (jupyter-subscriber
                    (lambda (x) (setq n (* x 3))))))
        (should-error
         (jupyter-run-with-io sub
           (jupyter-subscribe (jupyter-publisher)))
         :type 'jupyter-subscribed-subscriber)
        (should-error (funcall sub 'any))))
    ;; FIXME: Prevent ert from catching the error
    ;; (ert-info ("Keep subscriber on subscriber error")
    ;;   (let* ((msgs '())
    ;;          (pub (jupyter-publisher))
    ;;          (sub (jupyter-subscriber
    ;;                 (lambda (n)
    ;;                   (if (= n 1) (error "(= n 1)")
    ;;                     (push n msgs))))))
    ;;     (jupyter-run-with-io pub
    ;;       (jupyter-subscribe sub))
    ;;     (cl-loop
    ;;      for x in '(1 2 3)
    ;;      do (jupyter-run-with-io pub
    ;;           (jupyter-publish x)))
    ;;     (should (equal '(3 2) msgs))))
    )
  ;; Extra for fun
  (let* ((lst '(1 2 3 4 5 6 7 8 9 10))
         (emitter (lambda (_) (jupyter-content (pop lst))))
         (pub (jupyter-publisher emitter))
         (collector (lambda (el)
                      (if el
                          ;; NOTE: Not a good idea to do in practice
                          ;; on large lists since it will cause lots
                          ;; of recursion.
                          (jupyter-run-with-io pub
                            (jupyter-publish 'next))
                        (jupyter-unsubscribe))))
         (sub (jupyter-publisher collector)))
    (jupyter-run-with-io pub
      (jupyter-do
        (jupyter-subscribe sub)
        (jupyter-publish 'start)))
    (should (null lst)))
  ;; NOTE: Same as above, creating a subscription cycle can cause
  ;; errors when the recursion is too deep.  See
  ;; `max-lisp-eval-depth'.
  (letrec ((n 10)
           (ping (jupyter-publisher
                   (lambda (_) (jupyter-content 'ping))))
           (pong (jupyter-publisher
                   (lambda (_)
                     (if (< (cl-decf n) 0)
                         (jupyter-unsubscribe)
                       (jupyter-content 'pong))))))
    (jupyter-run-with-io pong
      (jupyter-do
        (jupyter-subscribe ping)
        (jupyter-with-io ping
          (jupyter-do
            (jupyter-subscribe pong)
            (jupyter-publish 'play)))))
    (should (< n 0))))

(defun jupyter-test-dummy-msgs (req-id)
  `((:header (:msg_id ,(jupyter-new-uuid)
                      :msg_type "status"
                      :username "nathan"
                      :session "5c5b72e9-48c4ae02e3eb1ca272fb0275"
                      :date "2020-05-22T13:29:34.756271Z"
                      :version "5.3")
             :parent_header (:msg_id ,req-id
                                     :msg_type "execute_request"
                                     :version "5.3"
                                     :username "nathan"
                                     :session "7c1d195f-f10f-4c84-b5cc-ddba55e94689"
                                     :date "2020-05-22T08:29:34.744583-05:00")
             :metadata nil
             :content (:execution_state "busy") :buffers nil :channel "iopub")
    (:header (:msg_id ,(jupyter-new-uuid)
                      :msg_type "execute_reply"
                      :username "nathan"
                      :session "5c5b72e9-48c4ae02e3eb1ca272fb0275"
                      :date "2020-05-22T13:29:34.755354Z"
                      :version "5.3")
             :parent_header (:msg_id ,req-id
                                     :msg_type "execute_request"
                                     :version "5.3"
                                     :username "nathan"
                                     :session "7c1d195f-f10f-4c84-b5cc-ddba55e94689"
                                     :date "2020-05-22T08:29:34.744583-05:00")
             :metadata nil
             :content nil :buffers nil :channel "shell")
    (:header (:msg_id ,(jupyter-new-uuid)
                      :msg_type "status"
                      :username "nathan"
                      :session "5c5b72e9-48c4ae02e3eb1ca272fb0275"
                      :date "2020-05-22T13:29:34.756271Z"
                      :version "5.3")
             :parent_header (:msg_id ,req-id
                                     :msg_type "execute_request"
                                     :version "5.3"
                                     :username "nathan"
                                     :session "7c1d195f-f10f-4c84-b5cc-ddba55e94689"
                                     :date "2020-05-22T08:29:34.744583-05:00")
             :metadata nil
             :content (:execution_state "idle") :buffers nil :channel "iopub")))

(ert-deftest fix-req-unsubscribe-mechanic ()
  :tags '(monad)
  (let ((unsubed-reqs '()))
    (cl-labels ((idle-p
                 (req)
                 (jupyter-request-idle-p req))
                (req-msg-p
                 (req msg)
                 (string= (jupyter-request-id req)
                          (jupyter-message-parent-id msg)))
                (make-req-pub
                 (req)
                 (jupyter-publisher
                   (lambda (msg)
                     (cond
                      ((idle-p req)
                       (push req unsubed-reqs)
                       (jupyter-unsubscribe))
                      ((req-msg-p req msg)
                       (when (jupyter-message-status-idle-p msg)
                         (setf (jupyter-request-idle-p req) t))
                       (jupyter-content msg)))))))
      (let* ((req1 (make-jupyter-request))
             (req2 (make-jupyter-request))
             (lst (append (jupyter-test-dummy-msgs
                           (jupyter-request-id req1))
                          (jupyter-test-dummy-msgs
                           (jupyter-request-id req2))))
             (initial-msgs (copy-sequence lst))
             (kernel-io (jupyter-publisher
                          (lambda (_)
                            (when lst
                              (jupyter-content (pop lst))))))
             (client-msgs '())
             (client-sub (jupyter-subscriber
                           (lambda (msg)
                             (push msg client-msgs)))))
        
        ;; A subscription chain for REQ1 (KIO -> REQ-PUB -> CLIENT-SUB)
        (let ((req-pub (make-req-pub req1)))
          (jupyter-run-with-io kernel-io
            (jupyter-subscribe req-pub))
          (jupyter-run-with-io req-pub
            (jupyter-subscribe client-sub)))
        ;; Send a message down the chain
        (jupyter-run-with-io kernel-io
          (jupyter-publish 'emit))
        ;; Another chain for REQ2.
        (let ((req-pub (make-req-pub req2)))
          (jupyter-run-with-io kernel-io
            (jupyter-subscribe req-pub))
          (jupyter-run-with-io req-pub
            (jupyter-subscribe client-sub)))
        ;; Send five messages.  Now REQ1 and REQ2 messages will be
        ;; received by CLIENT-SUB.
        (cl-loop
         repeat 5
         do (jupyter-run-with-io kernel-io
              (jupyter-publish 'emit)))
        (should (memq req1 unsubed-reqs))
        (should (equal initial-msgs (reverse client-msgs)))))))

(ert-deftest jupyter-subscriber-error ()
  :tags '(monad)
  ;; Test that a subscriber that raises an error just gets skipped
  ;; over, not removed.
  (let ((called1 0)
        (called2 0))
    (let ((sub1 (jupyter-subscriber
                  (lambda (msg)
                    (setq called1 (1+ called1)))))
          (sub2 (jupyter-subscriber
                  (lambda (msg)
                    (setq called2 (1+ called2))
                    (error "Subscriber error"))))
          (pub (jupyter-publisher #'jupyter-content)))
      (jupyter-run-with-io pub
        (jupyter-do
          (jupyter-subscribe sub2)
          (jupyter-subscribe sub1)))
      (should-error
       (jupyter-run-with-io pub
         (jupyter-publish 'msg)))
      (should (eq called1 1))
      (should (eq called2 1))
      (should-error
       (jupyter-run-with-io pub
         (jupyter-publish 'msg)))
      (should (eq called1 2))
      (should (eq called2 2))
      (should-error
       (jupyter-run-with-io pub
         (jupyter-publish 'msg)))
      (should (eq called1 3))
      (should (eq called2 3)))))

(ert-deftest jupyter-subscriber-skipping ()
  :tags '(monad)
  ;; Test that subscribers evaluation doesn't get skipped whenever a
  ;; previous subscriber unsubscribes.
  (let* ((count1 0)
         (count2 0)
         (count3 0)
         (sub1
          (jupyter-subscriber
            (lambda (msg)
              (setq count1 (1+ count1)))))
         (sub2
          (jupyter-subscriber
            (lambda (msg)
              (setq count2 (1+ count2))
              (jupyter-unsubscribe))))
         (sub3
          (jupyter-subscriber
            (lambda (msg)
              (setq count3 (1+ count3)))))
         (pub (jupyter-publisher #'jupyter-content)))
    (jupyter-run-with-io pub
      (jupyter-do
        (jupyter-subscribe sub3)
        (jupyter-subscribe sub2)
        (jupyter-subscribe sub1)))
    (jupyter-run-with-io pub
      (jupyter-publish 'msg))
    (should (eq count1 1))
    (should (eq count2 1))
    (should (eq count3 1))
    (jupyter-run-with-io pub
      (jupyter-publish 'msg))
    (should (eq count1 2))
    (should (eq count2 1))
    (should (eq count3 2))))

;; - `seq-elt'
;; - `seq-length'
;; - `seq-do'
;; - `seqp'
;; - `seq-subseq'
;; - `seq-into-sequence'
;; - `seq-copy'
;; - `seq-into'
(ert-deftest jupyter-seq-interface ()
  :tags '(monad seq)

  )

;;; jupyter-monad-test.el ends here
