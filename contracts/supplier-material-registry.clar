;; supplier-material-registry
;; Register PCR/biobased feedstock suppliers and audit attestations

;; constants
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-SUPPLIER-NOT-FOUND (err u102))
(define-constant ERR-SUPPLIER-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-PERCENTAGE (err u104))
(define-constant ERR-ATTESTATION-NOT-FOUND (err u105))
(define-constant ERR-MATERIAL-NOT-FOUND (err u106))

;; data maps and vars
(define-data-var contract-owner principal tx-sender)
(define-data-var next-supplier-id uint u1)
(define-data-var next-material-id uint u1)
(define-data-var next-attestation-id uint u1)

;; Supplier registry
(define-map suppliers
  { supplier-id: uint }
  {
    name: (string-ascii 100),
    principal: principal,
    certification-level: (string-ascii 50),
    registration-date: uint,
    status: bool,
    total-materials: uint
  }
)

;; Material registry
(define-map materials
  {
    material-id: uint
  }
  {
    supplier-id: uint,
    material-type: (string-ascii 50),
    pcr-percentage: uint,
    biobased-percentage: uint,
    origin-location: (string-ascii 100),
    certification-body: (string-ascii 100),
    quality-grade: (string-ascii 20),
    registration-date: uint,
    verification-status: bool
  }
)

;; Audit attestations
(define-map attestations
  {
    attestation-id: uint
  }
  {
    supplier-id: uint,
    material-id: uint,
    auditor: principal,
    attestation-date: uint,
    validity-period: uint,
    pcr-verified: bool,
    biobased-verified: bool,
    compliance-score: uint,
    notes: (string-ascii 200)
  }
)

;; Supplier lookup by principal
(define-map supplier-principals
  { principal: principal }
  { supplier-id: uint }
)

;; private functions
(define-private (is-contract-owner (caller principal))
  (is-eq caller (var-get contract-owner))
)

(define-private (is-authorized-supplier (caller principal))
  (match (map-get? supplier-principals { principal: caller })
    supplier-data
      (match (map-get? suppliers { supplier-id: (get supplier-id supplier-data) })
        supplier-info (get status supplier-info)
        false
      )
    false
  )
)

(define-private (validate-percentage (percentage uint))
  (<= percentage u100)
)

;; public functions

;; Register a new supplier
(define-public (register-supplier 
  (name (string-ascii 100))
  (certification-level (string-ascii 50))
  (supplier-principal principal)
)
  (let (
    (current-id (var-get next-supplier-id))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    (asserts! (is-none (map-get? supplier-principals { principal: supplier-principal })) ERR-SUPPLIER-ALREADY-EXISTS)
    
    ;; Register supplier
    (map-set suppliers
      { supplier-id: current-id }
      {
        name: name,
        principal: supplier-principal,
        certification-level: certification-level,
        registration-date: stacks-block-height,
        status: true,
        total-materials: u0
      }
    )
    
    ;; Create principal lookup
    (map-set supplier-principals
      { principal: supplier-principal }
      { supplier-id: current-id }
    )
    
    ;; Increment supplier ID
    (var-set next-supplier-id (+ current-id u1))
    
    (ok current-id)
  )
)

;; Register a new material
(define-public (register-material
  (material-type (string-ascii 50))
  (pcr-percentage uint)
  (biobased-percentage uint)
  (origin-location (string-ascii 100))
  (certification-body (string-ascii 100))
  (quality-grade (string-ascii 20))
)
  (let (
    (current-material-id (var-get next-material-id))
    (supplier-data (unwrap! (map-get? supplier-principals { principal: tx-sender }) ERR-NOT-AUTHORIZED))
    (supplier-id (get supplier-id supplier-data))
  )
    (asserts! (validate-percentage pcr-percentage) ERR-INVALID-PERCENTAGE)
    (asserts! (validate-percentage biobased-percentage) ERR-INVALID-PERCENTAGE)
    (asserts! (is-authorized-supplier tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Register material
    (map-set materials
      { material-id: current-material-id }
      {
        supplier-id: supplier-id,
        material-type: material-type,
        pcr-percentage: pcr-percentage,
        biobased-percentage: biobased-percentage,
        origin-location: origin-location,
        certification-body: certification-body,
        quality-grade: quality-grade,
        registration-date: stacks-block-height,
        verification-status: false
      }
    )
    
    ;; Update supplier's total materials count
    (match (map-get? suppliers { supplier-id: supplier-id })
      supplier-info
        (map-set suppliers
          { supplier-id: supplier-id }
          (merge supplier-info { total-materials: (+ (get total-materials supplier-info) u1) })
        )
      false
    )
    
    ;; Increment material ID
    (var-set next-material-id (+ current-material-id u1))
    
    (ok current-material-id)
  )
)

;; Create audit attestation
(define-public (create-attestation
  (material-id uint)
  (validity-period uint)
  (pcr-verified bool)
  (biobased-verified bool)
  (compliance-score uint)
  (notes (string-ascii 200))
)
  (let (
    (current-attestation-id (var-get next-attestation-id))
    (material-data (unwrap! (map-get? materials { material-id: material-id }) ERR-MATERIAL-NOT-FOUND))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    (asserts! (<= compliance-score u100) ERR-INVALID-PERCENTAGE)
    
    ;; Create attestation
    (map-set attestations
      { attestation-id: current-attestation-id }
      {
        supplier-id: (get supplier-id material-data),
        material-id: material-id,
        auditor: tx-sender,
        attestation-date: stacks-block-height,
        validity-period: validity-period,
        pcr-verified: pcr-verified,
        biobased-verified: biobased-verified,
        compliance-score: compliance-score,
        notes: notes
      }
    )
    
    ;; Update material verification status
    (map-set materials
      { material-id: material-id }
      (merge material-data { verification-status: (and pcr-verified biobased-verified) })
    )
    
    ;; Increment attestation ID
    (var-set next-attestation-id (+ current-attestation-id u1))
    
    (ok current-attestation-id)
  )
)

;; Update supplier status
(define-public (update-supplier-status (supplier-id uint) (status bool))
  (let (
    (supplier-data (unwrap! (map-get? suppliers { supplier-id: supplier-id }) ERR-SUPPLIER-NOT-FOUND))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    
    (map-set suppliers
      { supplier-id: supplier-id }
      (merge supplier-data { status: status })
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-supplier (supplier-id uint))
  (map-get? suppliers { supplier-id: supplier-id })
)

(define-read-only (get-material (material-id uint))
  (map-get? materials { material-id: material-id })
)

(define-read-only (get-attestation (attestation-id uint))
  (map-get? attestations { attestation-id: attestation-id })
)

(define-read-only (get-supplier-by-principal (supplier-principal principal))
  (match (map-get? supplier-principals { principal: supplier-principal })
    supplier-data (map-get? suppliers { supplier-id: (get supplier-id supplier-data) })
    none
  )
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (get-next-ids)
  {
    next-supplier-id: (var-get next-supplier-id),
    next-material-id: (var-get next-material-id),
    next-attestation-id: (var-get next-attestation-id)
  }
)

