;; Distributed Backup Contract
;; Ensures redundancy across multiple locations

(define-data-var admin principal tx-sender)

;; Map of backup locations
(define-map backup-locations
{ location-id: (string-ascii 32) }
{
  name: (string-ascii 64),
  description: (string-ascii 256),
  location-type: (string-ascii 32),
  geographic-region: (string-ascii 64),
  operator: principal,
  status: (string-ascii 16),
  reliability-score: uint,
  registered-at: uint
}
)

;; Map of document backups
(define-map document-backups
{
  document-id: (string-ascii 32),
  location-id: (string-ascii 32)
}
{
  backup-hash: (buff 32),
  backup-time: uint,
  verified-at: (optional uint),
  status: (string-ascii 16),
  encryption-type: (string-ascii 32)
}
)

;; Map of backup verification records
(define-map backup-verifications
{
  document-id: (string-ascii 32),
  location-id: (string-ascii 32),
  verification-id: uint
}
{
  verified-by: principal,
  verification-time: uint,
  verification-result: (string-ascii 16),
  notes: (string-ascii 256)
}
)

;; Map of backup policies
(define-map backup-policies
{ document-id: (string-ascii 32) }
{
  owner: principal,
  min-backup-count: uint,
  backup-frequency-hours: uint,
  verification-frequency-hours: uint,
  encryption-required: bool,
  last-policy-update: uint
}
)

;; Register a backup location
(define-public (register-location
  (location-id (string-ascii 32))
  (name (string-ascii 64))
  (description (string-ascii 256))
  (location-type (string-ascii 32))
  (geographic-region (string-ascii 64)))
(let ((current-time (default-to u0 (get-block-info? time u0))))
  (asserts! (or (is-eq tx-sender (var-get admin)) (is-approved-operator tx-sender)) (err u403))

  (map-insert backup-locations
    { location-id: location-id }
    {
      name: name,
      description: description,
      location-type: location-type,
      geographic-region: geographic-region,
      operator: tx-sender,
      status: "active",
      reliability-score: u80,  ;; Default score out of 100
      registered-at: current-time
    }
  )

  (ok true)
)
)

;; Create a backup policy for a document
(define-public (create-backup-policy
  (document-id (string-ascii 32))
  (min-backup-count uint)
  (backup-frequency-hours uint)
  (verification-frequency-hours uint)
  (encryption-required bool))
(let ((current-time (default-to u0 (get-block-info? time u0))))
  ;; In a real implementation, we would check if the caller owns the document
  ;; For simplicity, we'll just check if a policy already exists
  (asserts! (not (is-some (map-get? backup-policies { document-id: document-id }))) (err u403))

  (map-insert backup-policies
    { document-id: document-id }
    {
      owner: tx-sender,
      min-backup-count: min-backup-count,
      backup-frequency-hours: backup-frequency-hours,
      verification-frequency-hours: verification-frequency-hours,
      encryption-required: encryption-required,
      last-policy-update: current-time
    }
  )

  (ok true)
)
)

;; Record a document backup
(define-public (record-backup
  (document-id (string-ascii 32))
  (location-id (string-ascii 32))
  (backup-hash (buff 32))
  (encryption-type (string-ascii 32)))
(let ((location (unwrap! (map-get? backup-locations { location-id: location-id }) (err u404)))
      (policy (unwrap! (map-get? backup-policies { document-id: document-id }) (err u404)))
      (current-time (default-to u0 (get-block-info? time u0))))
  (asserts! (or
    (is-eq tx-sender (get owner policy))
    (is-eq tx-sender (get operator location))
    (is-eq tx-sender (var-get admin))
  ) (err u403))

  (map-insert document-backups
    {
      document-id: document-id,
      location-id: location-id
    }
    {
      backup-hash: backup-hash,
      backup-time: current-time,
      verified-at: none,
      status: "active",
      encryption-type: encryption-type
    }
  )

  (ok true)
)
)

;; Verify a backup
(define-public (verify-backup
  (document-id (string-ascii 32))
  (location-id (string-ascii 32))
  (verification-result (string-ascii 16))
  (notes (string-ascii 256)))
(let ((backup (unwrap! (map-get? document-backups { document-id: document-id, location-id: location-id }) (err u404)))
      (location (unwrap! (map-get? backup-locations { location-id: location-id }) (err u404)))
      (current-time (default-to u0 (get-block-info? time u0))))
  (asserts! (or
    (is-eq tx-sender (var-get admin))
    (is-eq tx-sender (get operator location))
    (is-approved-verifier tx-sender)
  ) (err u403))

  ;; Update backup verification time
  (map-set document-backups
    {
      document-id: document-id,
      location-id: location-id
    }
    (merge backup {
      verified-at: (some current-time),
      status: (if (is-eq verification-result "success") "verified" "failed")
    })
  )

  ;; Record verification details
  (let ((verification-id (get-next-verification-id document-id location-id)))
    (map-insert backup-verifications
      {
        document-id: document-id,
        location-id: location-id,
        verification-id: verification-id
      }
      {
        verified-by: tx-sender,
        verification-time: current-time,
        verification-result: verification-result,
        notes: notes
      }
    )
  )

  (ok true)
)
)

;; Update location status
(define-public (update-location-status
  (location-id (string-ascii 32))
  (status (string-ascii 16)))
(let ((location (unwrap! (map-get? backup-locations { location-id: location-id }) (err u404))))
  (asserts! (or
    (is-eq tx-sender (var-get admin))
    (is-eq tx-sender (get operator location))
  ) (err u403))

  (map-set backup-locations
    { location-id: location-id }
    (merge location { status: status })
  )

  (ok true)
)
)

;; Update location reliability score
(define-public (update-reliability-score
  (location-id (string-ascii 32))
  (reliability-score uint))
(let ((location (unwrap! (map-get? backup-locations { location-id: location-id }) (err u404))))
  (asserts! (is-eq tx-sender (var-get admin)) (err u403))
  (asserts! (<= reliability-score u100) (err u400))

  (map-set backup-locations
    { location-id: location-id }
    (merge location { reliability-score: reliability-score })
  )

  (ok true)
)
)

;; Helper function to check if principal is an approved operator
(define-private (is-approved-operator (operator principal))
;; In a real implementation, this would check against a list of approved operators
;; For simplicity, we'll just return true for now
true
)

;; Helper function to check if principal is an approved verifier
(define-private (is-approved-verifier (verifier principal))
;; In a real implementation, this would check against a list of approved verifiers
;; For simplicity, we'll just return true for now
true
)

;; Helper function to get the next verification ID
(define-private (get-next-verification-id (document-id (string-ascii 32)) (location-id (string-ascii 32)))
;; In a real implementation, this would track and increment verification IDs
;; For simplicity, we'll just return 1 for now
u1
)

;; Get backup location details
(define-read-only (get-backup-location (location-id (string-ascii 32)))
(map-get? backup-locations { location-id: location-id })
)

;; Get document backup details
(define-read-only (get-document-backup (document-id (string-ascii 32)) (location-id (string-ascii 32)))
(map-get? document-backups { document-id: document-id, location-id: location-id })
)

;; Get backup policy
(define-read-only (get-backup-policy (document-id (string-ascii 32)))
(map-get? backup-policies { document-id: document-id })
)

;; Get backup verification
(define-read-only (get-backup-verification
  (document-id (string-ascii 32))
  (location-id (string-ascii 32))
  (verification-id uint))
(map-get? backup-verifications
  {
    document-id: document-id,
    location-id: location-id,
    verification-id: verification-id
  }
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

