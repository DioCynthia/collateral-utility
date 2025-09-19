;; Collateral Utility Smart Contract
;; This contract manages business document collateralization and tracking on the Stacks blockchain.
;; It enables secure document referencing, permission management, and audit logging for financial collateral processes.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-COLLATERAL-ALREADY-EXISTS (err u201))
(define-constant ERR-COLLATERAL-NOT-FOUND (err u202))
(define-constant ERR-DOCUMENT-ALREADY-REGISTERED (err u203))
(define-constant ERR-DOCUMENT-NOT-FOUND (err u204))
(define-constant ERR-INVALID-PERMISSION-LEVEL (err u205))
(define-constant ERR-NO-ACCESS (err u206))

;; Permission levels
(define-constant PERMISSION-NONE u0)
(define-constant PERMISSION-VIEW u1)
(define-constant PERMISSION-MANAGE u2)
(define-constant PERMISSION-ADMIN u3)
(define-constant PERMISSION-OWNER u4)

;; Action types for audit log
(define-constant ACTION-CREATE u1)
(define-constant ACTION-VIEW u2)
(define-constant ACTION-UPDATE u3)
(define-constant ACTION-SHARE u4)
(define-constant ACTION-DELETE u5)

;; Data maps

;; Stores registered collateral entities
(define-map collateral-entities
  { entity-id: (string-ascii 64) }
  { 
    owner: principal,
    name: (string-ascii 256),
    registration-time: uint,
    active: bool
  }
)

;; Stores document metadata for collateralization
(define-map collateral-documents
  { entity-id: (string-ascii 64), document-id: (string-ascii 64) }
  {
    name: (string-ascii 256),
    description: (string-utf8 500),
    document-hash: (buff 32),
    document-type: (string-ascii 64),
    creation-time: uint,
    last-modified: uint,
    version: uint,
    active: bool
  }
)

;; Manages access permissions for documents
(define-map document-permissions
  { entity-id: (string-ascii 64), document-id: (string-ascii 64), user: principal }
  {
    permission-level: uint,
    granted-by: principal,
    granted-at: uint
  }
)

;; Maintains a comprehensive audit trail of document interactions
(define-map audit-logs
  { entity-id: (string-ascii 64), document-id: (string-ascii 64), log-id: uint }
  {
    user: principal,
    action: uint,
    timestamp: uint,
    details: (string-utf8 500)
  }
)

;; Tracks the next audit log ID for each document
(define-map audit-log-counters
  { entity-id: (string-ascii 64), document-id: (string-ascii 64) }
  { next-id: uint }
)

;; Private helper functions

;; Gets the next audit log ID and increments the counter
(define-private (get-next-audit-log-id (entity-id (string-ascii 64)) (document-id (string-ascii 64)))
  (let ((counter (default-to { next-id: u1 } (map-get? audit-log-counters { entity-id: entity-id, document-id: document-id }))))
    (begin
      (map-set audit-log-counters 
        { entity-id: entity-id, document-id: document-id }
        { next-id: (+ (get next-id counter) u1) }
      )
      (get next-id counter)
    )
  )
)

;; Creates a new audit log entry
(define-private (log-audit-event
  (entity-id (string-ascii 64))
  (document-id (string-ascii 64))
  (user principal)
  (action uint)
  (details (string-utf8 500))
)
  (let ((log-id (get-next-audit-log-id entity-id document-id)))
    (map-set audit-logs
      { entity-id: entity-id, document-id: document-id, log-id: log-id }
      {
        user: user,
        action: action,
        timestamp: block-height,
        details: details
      }
    )
    true
  )
)

;; Checks if a user has sufficient permission for a document
(define-private (has-permission
  (entity-id (string-ascii 64))
  (document-id (string-ascii 64))
  (user principal)
  (required-permission uint)
)
  (let (
    (entity-data (map-get? collateral-entities { entity-id: entity-id }))
    (permission-data (map-get? document-permissions { entity-id: entity-id, document-id: document-id, user: user }))
  )
    (if (is-none entity-data)
      false
      (if (is-eq (get owner (unwrap-panic entity-data)) user)
        true ;; Entity owner has full access
        (if (is-none permission-data)
          false
          (>= (get permission-level (unwrap-panic permission-data)) required-permission)
        )
      )
    )
  )
)

;; Validates if a document exists
(define-private (document-exists (entity-id (string-ascii 64)) (document-id (string-ascii 64)))
  (is-some (map-get? collateral-documents { entity-id: entity-id, document-id: document-id }))
)

;; Public functions

;; Registers a new collateral entity
(define-public (register-entity (entity-id (string-ascii 64)) (name (string-ascii 256)))
  (let ((existing-entity (map-get? collateral-entities { entity-id: entity-id })))
    (if (is-some existing-entity)
      ERR-COLLATERAL-ALREADY-EXISTS
      (begin
        (map-set collateral-entities
          { entity-id: entity-id }
          {
            owner: tx-sender,
            name: name,
            registration-time: block-height,
            active: true
          }
        )
        (ok true)
      )
    )
  )
)

;; Adds a new document for collateralization
(define-public (add-document
  (entity-id (string-ascii 64))
  (document-id (string-ascii 64))
  (name (string-ascii 256))
  (description (string-utf8 500))
  (document-hash (buff 32))
  (document-type (string-ascii 64))
)
  (let ((entity-data (map-get? collateral-entities { entity-id: entity-id })))
    (if (is-none entity-data)
      ERR-COLLATERAL-NOT-FOUND
      (if (not (is-eq (get owner (unwrap-panic entity-data)) tx-sender))
        ERR-NOT-AUTHORIZED
        (if (document-exists entity-id document-id)
          ERR-DOCUMENT-ALREADY-REGISTERED
          (begin
            ;; Add the document
            (map-set collateral-documents
              { entity-id: entity-id, document-id: document-id }
              {
                name: name,
                description: description,
                document-hash: document-hash,
                document-type: document-type,
                creation-time: block-height,
                last-modified: block-height,
                version: u1,
                active: true
              }
            )
            ;; Auto-assign owner permission
            (map-set document-permissions
              { entity-id: entity-id, document-id: document-id, user: tx-sender }
              {
                permission-level: PERMISSION-OWNER,
                granted-by: tx-sender,
                granted-at: block-height
              }
            )
            ;; Log the creation
            (log-audit-event entity-id document-id tx-sender ACTION-CREATE u"Document registered for collateral")
            (ok true)
          )
        )
      )
    )
  )
)

;; Updates an existing collateral document
(define-public (update-document
  (entity-id (string-ascii 64))
  (document-id (string-ascii 64))
  (name (string-ascii 256))
  (description (string-utf8 500))
  (document-hash (buff 32))
  (document-type (string-ascii 64))
)
  (let (
    (document-data (map-get? collateral-documents { entity-id: entity-id, document-id: document-id }))
  )
    (if (is-none document-data)
      ERR-DOCUMENT-NOT-FOUND
      (if (not (has-permission entity-id document-id tx-sender PERMISSION-MANAGE))
        ERR-NOT-AUTHORIZED
        (begin
          (map-set collateral-documents
            { entity-id: entity-id, document-id: document-id }
            {
              name: name,
              description: description,
              document-hash: document-hash,
              document-type: document-type,
              creation-time: (get creation-time (unwrap-panic document-data)),
              last-modified: block-height,
              version: (+ (get version (unwrap-panic document-data)) u1),
              active: true
            }
          )
          (log-audit-event entity-id document-id tx-sender ACTION-UPDATE u"Collateral document updated")
          (ok true)
        )
      )
    )
  )
)

;; Grants permission to a user for a document
(define-public (grant-document-permission
  (entity-id (string-ascii 64))
  (document-id (string-ascii 64))
  (user principal)
  (permission-level uint)
)
  (if (not (has-permission entity-id document-id tx-sender PERMISSION-ADMIN))
    ERR-NOT-AUTHORIZED
    (if (not (document-exists entity-id document-id))
      ERR-DOCUMENT-NOT-FOUND
      (if (or (< permission-level PERMISSION-VIEW) (> permission-level PERMISSION-ADMIN))
        ERR-INVALID-PERMISSION-LEVEL
        (begin
          (map-set document-permissions
            { entity-id: entity-id, document-id: document-id, user: user }
            {
              permission-level: permission-level,
              granted-by: tx-sender,
              granted-at: block-height
            }
          )
          (log-audit-event 
            entity-id 
            document-id 
            tx-sender 
            ACTION-SHARE 
            u"Permission granted to user"
          )
          (ok true)
        )
      )
    )
  )
)

;; Revokes permission from a user for a document
(define-public (revoke-document-permission
  (entity-id (string-ascii 64))
  (document-id (string-ascii 64))
  (user principal)
)
  (if (not (has-permission entity-id document-id tx-sender PERMISSION-ADMIN))
    ERR-NOT-AUTHORIZED
    (if (not (document-exists entity-id document-id))
      ERR-DOCUMENT-NOT-FOUND
      (begin
        (map-delete document-permissions { entity-id: entity-id, document-id: document-id, user: user })
        (log-audit-event 
          entity-id 
          document-id 
          tx-sender 
          ACTION-SHARE 
          u"Permission revoked"
        )
        (ok true)
      )
    )
  )
)

;; Marks a document access (for audit purposes)
(define-public (access-document
  (entity-id (string-ascii 64))
  (document-id (string-ascii 64))
)
  (if (not (has-permission entity-id document-id tx-sender PERMISSION-VIEW))
    ERR-NO-ACCESS
    (if (not (document-exists entity-id document-id))
      ERR-DOCUMENT-NOT-FOUND
      (begin
        (log-audit-event entity-id document-id tx-sender ACTION-VIEW u"Document accessed")
        (ok true)
      )
    )
  )
)

;; Soft deletes a document (marks as inactive)
(define-public (delete-document
  (entity-id (string-ascii 64))
  (document-id (string-ascii 64))
)
  (let (
    (document-data (map-get? collateral-documents { entity-id: entity-id, document-id: document-id }))
  )
    (if (is-none document-data)
      ERR-DOCUMENT-NOT-FOUND
      (if (not (has-permission entity-id document-id tx-sender PERMISSION-ADMIN))
        ERR-NOT-AUTHORIZED
        (begin
          (map-set collateral-documents
            { entity-id: entity-id, document-id: document-id }
            (merge (unwrap-panic document-data) { active: false })
          )
          (log-audit-event entity-id document-id tx-sender ACTION-DELETE u"Document deleted")
          (ok true)
        )
      )
    )
  )
)

;; Read-only functions

;; Gets entity information
(define-read-only (get-entity-info (entity-id (string-ascii 64)))
  (map-get? collateral-entities { entity-id: entity-id })
)

;; Gets document information
(define-read-only (get-document-info (entity-id (string-ascii 64)) (document-id (string-ascii 64)))
  (map-get? collateral-documents { entity-id: entity-id, document-id: document-id })
)

;; Checks the permission level of a user for a document
(define-read-only (get-user-permission (entity-id (string-ascii 64)) (document-id (string-ascii 64)) (user principal))
  (let (
    (entity-data (map-get? collateral-entities { entity-id: entity-id }))
    (permission-data (map-get? document-permissions { entity-id: entity-id, document-id: document-id, user: user }))
  )
    (if (is-none entity-data)
      (ok PERMISSION-NONE)
      (if (is-eq (get owner (unwrap-panic entity-data)) user)
        (ok PERMISSION-OWNER)
        (if (is-none permission-data)
          (ok PERMISSION-NONE)
          (ok (get permission-level (unwrap-panic permission-data)))
        )
      )
    )
  )
)

;; Gets a specific audit log entry
(define-read-only (get-audit-log-entry (entity-id (string-ascii 64)) (document-id (string-ascii 64)) (log-id uint))
  (map-get? audit-logs { entity-id: entity-id, document-id: document-id, log-id: log-id })
)

;; Utility functions for type conversion and demonstration purposes
(define-private (uint-to-ascii (value uint))
  (concat "u" (int-to-ascii value))
)

(define-private (int-to-ascii (value uint))
  (unwrap-panic (element-at 
    (list "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "10" "11" "12" "13" "14" "15")
    (if (> value u15) u0 value)
  ))
)