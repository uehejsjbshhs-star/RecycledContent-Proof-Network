;; content-claim-verification
;; Attach verified recycled content percentages to SKUs

;; constants
(define-constant ERR-OWNER-ONLY (err u200))
(define-constant ERR-NOT-AUTHORIZED (err u201))
(define-constant ERR-CLAIM-NOT-FOUND (err u202))
(define-constant ERR-CLAIM-ALREADY-EXISTS (err u203))
(define-constant ERR-INVALID-PERCENTAGE (err u204))
(define-constant ERR-SKU-NOT-FOUND (err u205))
(define-constant ERR-MANUFACTURER-NOT-FOUND (err u206))
(define-constant ERR-VERIFICATION-PENDING (err u207))
(define-constant ERR-VERIFICATION-FAILED (err u208))

;; data vars
(define-data-var contract-owner principal tx-sender)
(define-data-var next-claim-id uint u1)
(define-data-var next-manufacturer-id uint u1)
(define-data-var next-sku-id uint u1)

;; Manufacturer registry
(define-map manufacturers
  { manufacturer-id: uint }
  {
    name: (string-ascii 100),
    principal: principal,
    registration-date: uint,
    verified-status: bool,
    total-skus: uint,
    compliance-rating: uint
  }
)

;; SKU registry
(define-map skus
  {
    sku-id: uint
  }
  {
    manufacturer-id: uint,
    sku-code: (string-ascii 50),
    product-name: (string-ascii 100),
    category: (string-ascii 50),
    registration-date: uint,
    total-claims: uint
  }
)

;; Content claims
(define-map content-claims
  {
    claim-id: uint
  }
  {
    sku-id: uint,
    manufacturer-id: uint,
    pcr-percentage: uint,
    biobased-percentage: uint,
    claim-date: uint,
    verification-status: (string-ascii 20),
    verifier: (optional principal),
    verification-date: (optional uint),
    material-source-ids: (list 10 uint),
    documentation-hash: (string-ascii 64),
    consumer-visible: bool
  }
)

;; Verification history
(define-map verification-history
  {
    claim-id: uint,
    verification-round: uint
  }
  {
    verifier: principal,
    verification-date: uint,
    status: (string-ascii 20),
    evidence-score: uint,
    notes: (string-ascii 200)
  }
)

;; Manufacturer lookup by principal
(define-map manufacturer-principals
  { principal: principal }
  { manufacturer-id: uint }
)

;; SKU lookup by code
(define-map sku-codes
  { sku-code: (string-ascii 50) }
  { sku-id: uint }
)

;; private functions
(define-private (is-contract-owner (caller principal))
  (is-eq caller (var-get contract-owner))
)

(define-private (is-authorized-manufacturer (caller principal))
  (match (map-get? manufacturer-principals { principal: caller })
    manufacturer-data
      (match (map-get? manufacturers { manufacturer-id: (get manufacturer-id manufacturer-data) })
        manufacturer-info (get verified-status manufacturer-info)
        false
      )
    false
  )
)

(define-private (validate-percentage (percentage uint))
  (<= percentage u100)
)

(define-private (calculate-compliance-score (pcr-percentage uint) (biobased-percentage uint))
  (+ (* pcr-percentage u2) biobased-percentage)
)

;; public functions

;; Register a new manufacturer
(define-public (register-manufacturer
  (name (string-ascii 100))
  (manufacturer-principal principal)
)
  (let (
    (current-id (var-get next-manufacturer-id))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    (asserts! (is-none (map-get? manufacturer-principals { principal: manufacturer-principal })) ERR-CLAIM-ALREADY-EXISTS)
    
    ;; Register manufacturer
    (map-set manufacturers
      { manufacturer-id: current-id }
      {
        name: name,
        principal: manufacturer-principal,
        registration-date: stacks-block-height,
        verified-status: false,
        total-skus: u0,
        compliance-rating: u0
      }
    )
    
    ;; Create principal lookup
    (map-set manufacturer-principals
      { principal: manufacturer-principal }
      { manufacturer-id: current-id }
    )
    
    ;; Increment manufacturer ID
    (var-set next-manufacturer-id (+ current-id u1))
    
    (ok current-id)
  )
)

;; Register a new SKU
(define-public (register-sku
  (sku-code (string-ascii 50))
  (product-name (string-ascii 100))
  (category (string-ascii 50))
)
  (let (
    (current-sku-id (var-get next-sku-id))
    (manufacturer-data (unwrap! (map-get? manufacturer-principals { principal: tx-sender }) ERR-NOT-AUTHORIZED))
    (manufacturer-id (get manufacturer-id manufacturer-data))
  )
    (asserts! (is-authorized-manufacturer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? sku-codes { sku-code: sku-code })) ERR-CLAIM-ALREADY-EXISTS)
    
    ;; Register SKU
    (map-set skus
      { sku-id: current-sku-id }
      {
        manufacturer-id: manufacturer-id,
        sku-code: sku-code,
        product-name: product-name,
        category: category,
        registration-date: stacks-block-height,
        total-claims: u0
      }
    )
    
    ;; Create SKU code lookup
    (map-set sku-codes
      { sku-code: sku-code }
      { sku-id: current-sku-id }
    )
    
    ;; Update manufacturer's total SKUs
    (match (map-get? manufacturers { manufacturer-id: manufacturer-id })
      manufacturer-info
        (map-set manufacturers
          { manufacturer-id: manufacturer-id }
          (merge manufacturer-info { total-skus: (+ (get total-skus manufacturer-info) u1) })
        )
      false
    )
    
    ;; Increment SKU ID
    (var-set next-sku-id (+ current-sku-id u1))
    
    (ok current-sku-id)
  )
)

;; Create content claim
(define-public (create-content-claim
  (sku-code (string-ascii 50))
  (pcr-percentage uint)
  (biobased-percentage uint)
  (material-source-ids (list 10 uint))
  (documentation-hash (string-ascii 64))
)
  (let (
    (current-claim-id (var-get next-claim-id))
    (manufacturer-data (unwrap! (map-get? manufacturer-principals { principal: tx-sender }) ERR-NOT-AUTHORIZED))
    (manufacturer-id (get manufacturer-id manufacturer-data))
    (sku-data (unwrap! (map-get? sku-codes { sku-code: sku-code }) ERR-SKU-NOT-FOUND))
    (sku-id (get sku-id sku-data))
  )
    (asserts! (validate-percentage pcr-percentage) ERR-INVALID-PERCENTAGE)
    (asserts! (validate-percentage biobased-percentage) ERR-INVALID-PERCENTAGE)
    (asserts! (is-authorized-manufacturer tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Create content claim
    (map-set content-claims
      { claim-id: current-claim-id }
      {
        sku-id: sku-id,
        manufacturer-id: manufacturer-id,
        pcr-percentage: pcr-percentage,
        biobased-percentage: biobased-percentage,
        claim-date: stacks-block-height,
        verification-status: "pending",
        verifier: none,
        verification-date: none,
        material-source-ids: material-source-ids,
        documentation-hash: documentation-hash,
        consumer-visible: false
      }
    )
    
    ;; Update SKU's total claims
    (match (map-get? skus { sku-id: sku-id })
      sku-info
        (map-set skus
          { sku-id: sku-id }
          (merge sku-info { total-claims: (+ (get total-claims sku-info) u1) })
        )
      false
    )
    
    ;; Increment claim ID
    (var-set next-claim-id (+ current-claim-id u1))
    
    (ok current-claim-id)
  )
)

;; Verify content claim
(define-public (verify-content-claim
  (claim-id uint)
  (verification-status (string-ascii 20))
  (evidence-score uint)
  (notes (string-ascii 200))
)
  (let (
    (claim-data (unwrap! (map-get? content-claims { claim-id: claim-id }) ERR-CLAIM-NOT-FOUND))
    (verification-round u1)
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    (asserts! (<= evidence-score u100) ERR-INVALID-PERCENTAGE)
    
    ;; Update claim verification status
    (map-set content-claims
      { claim-id: claim-id }
      (merge claim-data {
        verification-status: verification-status,
        verifier: (some tx-sender),
        verification-date: (some stacks-block-height),
        consumer-visible: (is-eq verification-status "verified")
      })
    )
    
    ;; Record verification history
    (map-set verification-history
      { claim-id: claim-id, verification-round: verification-round }
      {
        verifier: tx-sender,
        verification-date: stacks-block-height,
        status: verification-status,
        evidence-score: evidence-score,
        notes: notes
      }
    )
    
    ;; Update manufacturer compliance rating if verified
    (if (is-eq verification-status "verified")
      (let (
        (manufacturer-id (get manufacturer-id claim-data))
        (compliance-score (calculate-compliance-score (get pcr-percentage claim-data) (get biobased-percentage claim-data)))
      )
        (match (map-get? manufacturers { manufacturer-id: manufacturer-id })
          manufacturer-info
            (map-set manufacturers
              { manufacturer-id: manufacturer-id }
              (merge manufacturer-info {
                compliance-rating: (+ (get compliance-rating manufacturer-info) compliance-score)
              })
            )
          false
        )
      )
      true
    )
    
    (ok true)
  )
)

;; Update manufacturer verification status
(define-public (update-manufacturer-status (manufacturer-id uint) (verified-status bool))
  (let (
    (manufacturer-data (unwrap! (map-get? manufacturers { manufacturer-id: manufacturer-id }) ERR-MANUFACTURER-NOT-FOUND))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    
    (map-set manufacturers
      { manufacturer-id: manufacturer-id }
      (merge manufacturer-data { verified-status: verified-status })
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-manufacturer (manufacturer-id uint))
  (map-get? manufacturers { manufacturer-id: manufacturer-id })
)

(define-read-only (get-sku (sku-id uint))
  (map-get? skus { sku-id: sku-id })
)

(define-read-only (get-sku-by-code (sku-code (string-ascii 50)))
  (match (map-get? sku-codes { sku-code: sku-code })
    sku-data (map-get? skus { sku-id: (get sku-id sku-data) })
    none
  )
)

(define-read-only (get-content-claim (claim-id uint))
  (map-get? content-claims { claim-id: claim-id })
)

(define-read-only (get-verification-history (claim-id uint) (verification-round uint))
  (map-get? verification-history { claim-id: claim-id, verification-round: verification-round })
)

(define-read-only (get-manufacturer-by-principal (manufacturer-principal principal))
  (match (map-get? manufacturer-principals { principal: manufacturer-principal })
    manufacturer-data (map-get? manufacturers { manufacturer-id: (get manufacturer-id manufacturer-data) })
    none
  )
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (get-next-ids)
  {
    next-claim-id: (var-get next-claim-id),
    next-manufacturer-id: (var-get next-manufacturer-id),
    next-sku-id: (var-get next-sku-id)
  }
)

;; Get verified claims for consumer verification
(define-read-only (get-verified-claims-for-sku (sku-code (string-ascii 50)))
  (match (map-get? sku-codes { sku-code: sku-code })
    sku-data
      (let (
        (sku-id (get sku-id sku-data))
      )
        ;; This would need to be implemented with a more complex query system
        ;; For now, we return the SKU info and recommend querying individual claims
        (map-get? skus { sku-id: sku-id })
      )
    none
  )
)

