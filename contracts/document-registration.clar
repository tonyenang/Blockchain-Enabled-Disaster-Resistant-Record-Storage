;; Document Registration Contract
;; Securely stores essential records

(define-data-var admin principal tx-sender)

;; Map of registered documents
(define-map documents
{ document-id: (string-ascii 32) }
{
  owner: principal,
  name: (string-ascii 64),
  description: (string-ascii 256),
  document-hash: (buff 32),
  category: (string-ascii 32),
  creation-time: uint,
  last-updated: uint,
  status: (string-ascii 16)
}
)

;; Map of document access permissions
(define-map document-access
{
  document-id: (string-ascii 32),
  user: principal
}
{
  granted-by: principal,
  access-level: (string-ascii 16),
  granted-at: uint,
  expires-at: (optional uint)
}
)

;; Map of document versions
(define-map document-versions
{
  document-id: (string-ascii 32),
  version: uint
}
{
  document-hash: (buff 32),
  updated-by: principal,
  update-time: uint,
  change-notes: (string-ascii 256)
}
)

;; Register a new document
(define-public (register-document
  (document-id (string-ascii 32))
  (name (string-ascii 64))
  (description (string-ascii 256))
  (document-hash (buff 32))
  (category (string-ascii 32)))
(let ((current-time (default-to u0 (get-block-info? time u0))))
  (asserts! (not (is-some (map-get? documents { document-id: document-id }))) (err u403))

  (map-insert documents
    { document-id: document-id }
    {
      owner: tx-sender,
      name: name,
      description: description,
      document-hash: document-hash,
      category: category,
      creation-time: current-time,
      last-updated: current-time,
      status: "active"
    }
  )

  ;; Record initial version
  (map-insert document-versions
    {
      document-id: document-id,
      version: u1
    }
    {
      document-hash: document-hash,
      updated-by: tx-sender,
      update-time: current-time,
      change-notes: "Initial document registration"
    }
  )

  (ok true)
)
)

;; Update document
(define-public (update-document
  (document-id (string-ascii 32))
  (name (string-ascii 64))
  (description (string-ascii 256))
  (document-hash (buff 32))
  (change-notes (string-ascii 256)))
(let ((doc (unwrap! (map-get? documents { document-id: document-id }) (err u404)))
      (current-time (default-to u0 (get-block-info? time u0))))
  (asserts! (is-eq (get owner doc) tx-sender) (err u403))

  ;; Update document metadata
  (map-set documents
    { document-id: document-id }
    (merge doc {
      name: name,
      description: description,
      document-hash: document-hash,
      last-updated: current-time
    })
  )

  ;; Get current version and increment
  (let ((current-version (get-document-current-version document-id)))
    (map-insert document-versions
      {
        document-id: document-id,
        version: (+ current-version u1)
      }
      {
        document-hash: document-hash,
        updated-by: tx-sender,
        update-time: current-time,
        change-notes: change-notes
      }
    )
  )

  (ok true)
)
)

;; Grant access to a document
(define-public (grant-access
  (document-id (string-ascii 32))
  (user principal)
  (access-level (string-ascii 16))
  (expires-at (optional uint)))
(let ((doc (unwrap! (map-get? documents { document-id: document-id }) (err u404)))
      (current-time (default-to u0 (get-block-info? time u0))))
  (asserts! (is-eq (get owner doc) tx-sender) (err u403))

  (map-insert document-access
    {
      document-id: document-id,
      user: user
    }
    {
      granted-by: tx-sender,
      access-level: access-level,
      granted-at: current-time,
      expires-at: expires-at
    }
  )

  (ok true)
)
)

;; Revoke access to a document
(define-public (revoke-access
  (document-id (string-ascii 32))
  (user principal))
(let ((doc (unwrap! (map-get? documents { document-id: document-id }) (err u404)))
      (access (unwrap! (map-get? document-access { document-id: document-id, user: user }) (err u404))))
  (asserts! (is-eq (get owner doc) tx-sender) (err u403))

  (map-delete document-access
    {
      document-id: document-id,
      user: user
    }
  )

  (ok true)
)
)

;; Change document status
(define-public (change-document-status
  (document-id (string-ascii 32))
  (status (string-ascii 16)))
(let ((doc (unwrap! (map-get? documents { document-id: document-id }) (err u404))))
  (asserts! (is-eq (get owner doc) tx-sender) (err u403))

  (map-set documents
    { document-id: document-id }
    (merge doc { status: status })
  )

  (ok true)
)
)

;; Transfer document ownership
(define-public (transfer-ownership
  (document-id (string-ascii 32))
  (new-owner principal))
(let ((doc (unwrap! (map-get? documents { document-id: document-id }) (err u404))))
  (asserts! (is-eq (get owner doc) tx-sender) (err u403))

  (map-set documents
    { document-id: document-id }
    (merge doc { owner: new-owner })
  )

  (ok true)
)
)

;; Helper function to get current version of a document
(define-private (get-document-current-version (document-id (string-ascii 32)))
(let ((doc (map-get? documents { document-id: document-id })))
  (if (is-some doc)
    ;; Simple approach: we could implement a more sophisticated version tracking
    ;; For now, we'll just use a counter based on creation time
    (let ((creation-time (get creation-time (unwrap! doc u0))))
      (if (> creation-time u0)
        u1  ;; At least version 1 if document exists
        u0  ;; Default if something went wrong
      )
    )
    u0  ;; Document doesn't exist
  )
)
)

;; Get document details
(define-read-only (get-document (document-id (string-ascii 32)))
(map-get? documents { document-id: document-id })
)

;; Get document version
(define-read-only (get-document-version (document-id (string-ascii 32)) (version uint))
(map-get? document-versions { document-id: document-id, version: version })
)

;; Check if user has access to document
(define-read-only (check-access (document-id (string-ascii 32)) (user principal))
(let ((access (map-get? document-access { document-id: document-id, user: user }))
      (current-time (default-to u0 (get-block-info? time u0))))
  (if (is-some access)
    (let ((access-data (default-to
                        {
                          granted-by: tx-sender,
                          access-level: "",
                          granted-at: u0,
                          expires-at: none
                        }
                        access))
          (expires-at (get expires-at access-data)))
      (if (is-some expires-at)
        (if (< current-time (default-to u0 expires-at))
          (ok true)  ;; Access is valid and not expired
          (ok false)  ;; Access has expired
        )
        (ok true)  ;; Access has no expiration
      )
    )
    (ok false)  ;; No access record found
  )
)
)

;; Transfer admin rights
(define-public (transfer-admin (new-admin principal))
(begin
  (asserts! (is-eq tx-sender (var-get admin)) (err u403))
  (var-set admin new-admin)
  (ok true)
)
)

