;; Access Recovery Contract
;; Provides emergency access after disasters

(define-data-var admin principal tx-sender)

;; Map of recovery agents
(define-map recovery-agents
{ agent-id: (string-ascii 32) }
{
  name: (string-ascii 64),
  organization: (string-ascii 64),
  agent-address: principal,
  status: (string-ascii 16),
  trust-score: uint,
  registered-at: uint
}
)

;; Map of document recovery settings
(define-map document-recovery
{ document-id: (string-ascii 32) }
{
  owner: principal,
  recovery-threshold: uint,
  recovery-delay-hours: uint,
  designated-recipients: (list 10 principal),
  last-updated: uint
}
)

;; Map of recovery requests
(define-map recovery-requests
{ request-id: (string-ascii 32) }
{
  document-id: (string-ascii 32),
  requester: principal,
  request-reason: (string-ascii 256),
  request-time: uint,
  status: (string-ascii 16),
  expiration-time: uint
}
)

;; Map of recovery approvals
(define-map recovery-approvals
{
  request-id: (string-ascii 32),
  agent-id: (string-ascii 32)
}
{
  approval-time: uint,
  notes: (string-ascii 256)
}
)

;; Map of recovery events
(define-map recovery-events
{ event-id: (string-ascii 32) }
{
  document-id: (string-ascii 32),
  request-id: (string-ascii 32),
  recipient: principal,
  recovery-time: uint,
  recovery-method: (string-ascii 32),
  recovery-notes: (string-ascii 256)
}
)

;; Register a recovery agent
(define-public (register-agent
  (agent-id (string-ascii 32))
  (name (string-ascii 64))
  (organization (string-ascii 64)))
(let ((current-time (default-to u0 (get-block-info? time u0))))
  (asserts! (is-eq tx-sender (var-get admin)) (err u403))

  (map-insert recovery-agents
    { agent-id: agent-id }
    {
      name: name,
      organization: organization,
      agent-address: tx-sender,
      status: "active",
      trust-score: u80,  ;; Default score out of 100
      registered-at: current-time
    }
  )

  (ok true)
)
)

;; Set document recovery settings
(define-public (set-recovery-settings
  (document-id (string-ascii 32))
  (recovery-threshold uint)
  (recovery-delay-hours uint)
  (designated-recipients (list 10 principal)))
(let ((current-time (default-to u0 (get-block-info? time u0))))
;; In a real implementation, we would check if the caller owns the document
;; For simplicity, we'll just check if recovery settings already exist
(let ((existing-settings (map-get? document-recovery { document-id: document-id })))
  (if (is-some existing-settings)
    (asserts! (is-eq (get owner (default-to { owner: tx-sender } existing-settings)) tx-sender) (err u403))
    true
  )
)

  (map-insert document-recovery
    { document-id: document-id }
    {
      owner: tx-sender,
      recovery-threshold: recovery-threshold,
      recovery-delay-hours: recovery-delay-hours,
      designated-recipients: designated-recipients,
      last-updated: current-time
    }
  )

  (ok true)
)
)

;; Create a recovery request
(define-public (create-recovery-request
  (request-id (string-ascii 32))
  (document-id (string-ascii 32))
  (request-reason (string-ascii 256)))
(let ((recovery-settings (unwrap! (map-get? document-recovery { document-id: document-id }) (err u404)))
      (current-time (default-to u0 (get-block-info? time u0))))
(asserts! (is-authorized-requester tx-sender document-id) (err u403))

  (map-insert recovery-requests
    { request-id: request-id }
    {
      document-id: document-id,
      requester: tx-sender,
      request-reason: request-reason,
      request-time: current-time,
      status: "pending",
      expiration-time: (+ current-time (* (get recovery-delay-hours recovery-settings) u3600))
    }
  )

  (ok true)
)
)

;; Approve a recovery request
(define-public (approve-recovery-request
  (request-id (string-ascii 32))
  (agent-id (string-ascii 32))
  (notes (string-ascii 256)))
(let ((request (unwrap! (map-get? recovery-requests { request-id: request-id }) (err u404)))
      (agent (unwrap! (map-get? recovery-agents { agent-id: agent-id }) (err u404)))
      (current-time (default-to u0 (get-block-info? time u0))))
  (asserts! (is-eq (get agent-address agent) tx-sender) (err u403))
  (asserts! (is-eq (get status agent) "active") (err u403))
  (asserts! (is-eq (get status request) "pending") (err u403))
  (asserts! (< current-time (get expiration-time request)) (err u400))

  (map-insert recovery-approvals
    {
      request-id: request-id,
      agent-id: agent-id
    }
    {
      approval-time: current-time,
      notes: notes
    }
  )

  ;; Check if threshold is met and update request status if needed
  (let ((approval-count (get-approval-count request-id))
        (document-id (get document-id request))
        (recovery-settings (unwrap! (map-get? document-recovery { document-id: document-id }) (err u404))))
    (if (>= approval-count (get recovery-threshold recovery-settings))
      (map-set recovery-requests
        { request-id: request-id }
        (merge request { status: "approved" })
      )
      true
    )
  )

  (ok true)
)
)

;; Execute recovery
(define-public (execute-recovery
  (event-id (string-ascii 32))
  (request-id (string-ascii 32))
  (recovery-method (string-ascii 32))
  (recovery-notes (string-ascii 256)))
(let ((request (unwrap! (map-get? recovery-requests { request-id: request-id }) (err u404)))
    (document-id (get document-id request))
    (current-time (default-to u0 (get-block-info? time u0))))
  (asserts! (is-eq (get status request) "approved") (err u403))
  (asserts! (or (is-eq tx-sender (var-get admin)) (is-recovery-agent tx-sender)) (err u403))

  (map-insert recovery-events
    { event-id: event-id }
    {
      document-id: document-id,
      request-id: request-id,
      recipient: (get requester request),
      recovery-time: current-time,
      recovery-method: recovery-method,
      recovery-notes: recovery-notes
    }
  )

  ;; Update request status
  (map-set recovery-requests
    { request-id: request-id }
    (merge request { status: "completed" })
  )

  (ok true)
)
)

;; Update agent status
(define-public (update-agent-status
  (agent-id (string-ascii 32))
  (status (string-ascii 16)))
(let ((agent (unwrap! (map-get? recovery-agents { agent-id: agent-id }) (err u404))))
  (asserts! (is-eq tx-sender (var-get admin)) (err u403))

  (map-set recovery-agents
    { agent-id: agent-id }
    (merge agent { status: status })
  )

  (ok true)
)
)

;; Update agent trust score
(define-public (update-trust-score
  (agent-id (string-ascii 32))
  (trust-score uint))
(let ((agent (unwrap! (map-get? recovery-agents { agent-id: agent-id }) (err u404))))
  (asserts! (is-eq tx-sender (var-get admin)) (err u403))
  (asserts! (<= trust-score u100) (err u400))

  (map-set recovery-agents
    { agent-id: agent-id }
    (merge agent { trust-score: trust-score })
  )

  (ok true)
)
)

;; Helper function to check if principal is authorized to request recovery
(define-private (is-authorized-requester (requester principal) (document-id (string-ascii 32)))
(let ((recovery-settings (map-get? document-recovery { document-id: document-id })))
  (if (is-some recovery-settings)
    (let ((settings (unwrap! recovery-settings false)))
      (or
        (is-eq requester (get owner settings))
        (is-some (index-of (get designated-recipients settings) requester))
      )
    )
    false
  )
)
)

;; Helper function to check if principal is a recovery agent
(define-private (is-recovery-agent (agent principal))
;; In a real implementation, this would check if the principal is a registered agent
;; For simplicity, we'll just return true for now
true
)

;; Helper function to get approval count for a request
(define-private (get-approval-count (request-id (string-ascii 32)))
;; In a real implementation, this would count the number of approvals
;; For simplicity, we'll just return 1 for now
u1
)

;; Get recovery agent details
(define-read-only (get-recovery-agent (agent-id (string-ascii 32)))
(map-get? recovery-agents { agent-id: agent-id })
)

;; Get document recovery settings
(define-read-only (get-recovery-settings (document-id (string-ascii 32)))
(map-get? document-recovery { document-id: document-id })
)

;; Get recovery request details
(define-read-only (get-recovery-request (request-id (string-ascii 32)))
(map-get? recovery-requests { request-id: request-id })
)

;; Get recovery approval
(define-read-only (get-recovery-approval (request-id (string-ascii 32)) (agent-id (string-ascii 32)))
(map-get? recovery-approvals { request-id: request-id, agent-id: agent-id })
)

;; Get recovery event
(define-read-only (get-recovery-event (event-id (string-ascii 32)))
(map-get? recovery-events { event-id: event-id })
)

;; Transfer admin rights
(define-public (transfer-admin (new-admin principal))
(begin
  (asserts! (is-eq tx-sender (var-get admin)) (err u403))
  (var-set admin new-admin)
  (ok true)
)
)

