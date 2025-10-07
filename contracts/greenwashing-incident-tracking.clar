;; greenwashing-incident-tracking
;; Flag inflated claims and resolve with third-party auditors

;; constants
(define-constant ERR-OWNER-ONLY (err u300))
(define-constant ERR-NOT-AUTHORIZED (err u301))
(define-constant ERR-INCIDENT-NOT-FOUND (err u302))
(define-constant ERR-INCIDENT-ALREADY-EXISTS (err u303))
(define-constant ERR-INVALID-SEVERITY (err u304))
(define-constant ERR-INVALID-STATUS (err u305))
(define-constant ERR-REPORTER-NOT-FOUND (err u306))
(define-constant ERR-AUDITOR-NOT-FOUND (err u307))
(define-constant ERR-RESOLUTION-NOT-FOUND (err u308))

;; Status constants
(define-constant STATUS-REPORTED "reported")
(define-constant STATUS-UNDER-REVIEW "under-review")
(define-constant STATUS-VERIFIED "verified")
(define-constant STATUS-DISMISSED "dismissed")
(define-constant STATUS-RESOLVED "resolved")

;; Severity levels
(define-constant SEVERITY-LOW u1)
(define-constant SEVERITY-MEDIUM u2)
(define-constant SEVERITY-HIGH u3)
(define-constant SEVERITY-CRITICAL u4)

;; data vars
(define-data-var contract-owner principal tx-sender)
(define-data-var next-incident-id uint u1)
(define-data-var next-reporter-id uint u1)
(define-data-var next-auditor-id uint u1)
(define-data-var next-resolution-id uint u1)

;; Reporter registry
(define-map reporters
  { reporter-id: uint }
  {
    principal: principal,
    name: (string-ascii 100),
    organization: (optional (string-ascii 100)),
    verification-level: uint,
    registration-date: uint,
    total-reports: uint,
    accuracy-score: uint
  }
)

;; Auditor registry
(define-map auditors
  { auditor-id: uint }
  {
    principal: principal,
    name: (string-ascii 100),
    certification: (string-ascii 100),
    specialization: (string-ascii 50),
    registration-date: uint,
    total-cases: uint,
    success-rate: uint,
    active-status: bool
  }
)

;; Incident reports
(define-map incidents
  {
    incident-id: uint
  }
  {
    reporter-id: uint,
    reported-entity: (string-ascii 100),
    entity-principal: (optional principal),
    claim-id: (optional uint),
    incident-type: (string-ascii 50),
    severity: uint,
    report-date: uint,
    status: (string-ascii 20),
    assigned-auditor: (optional uint),
    evidence-links: (list 5 (string-ascii 200)),
    description: (string-ascii 500),
    public-visibility: bool
  }
)

;; Resolution records
(define-map resolutions
  {
    resolution-id: uint
  }
  {
    incident-id: uint,
    auditor-id: uint,
    resolution-date: uint,
    final-status: (string-ascii 20),
    evidence-score: uint,
    penalty-amount: uint,
    corrective-actions: (string-ascii 500),
    follow-up-required: bool,
    public-report: (string-ascii 1000)
  }
)

;; Investigation history
(define-map investigation-logs
  {
    incident-id: uint,
    log-entry: uint
  }
  {
    auditor-id: uint,
    entry-date: uint,
    action-type: (string-ascii 50),
    notes: (string-ascii 300),
    evidence-collected: bool
  }
)

;; Principal lookups
(define-map reporter-principals
  { principal: principal }
  { reporter-id: uint }
)

(define-map auditor-principals
  { principal: principal }
  { auditor-id: uint }
)

;; private functions
(define-private (is-contract-owner (caller principal))
  (is-eq caller (var-get contract-owner))
)

(define-private (is-authorized-reporter (caller principal))
  (is-some (map-get? reporter-principals { principal: caller }))
)

(define-private (is-authorized-auditor (caller principal))
  (match (map-get? auditor-principals { principal: caller })
    auditor-data
      (match (map-get? auditors { auditor-id: (get auditor-id auditor-data) })
        auditor-info (get active-status auditor-info)
        false
      )
    false
  )
)

(define-private (validate-severity (severity uint))
  (and (>= severity SEVERITY-LOW) (<= severity SEVERITY-CRITICAL))
)

(define-private (calculate-penalty (severity uint) (evidence-score uint))
  (* severity evidence-score u10)
)

;; public functions

;; Register a new reporter
(define-public (register-reporter
  (reporter-principal principal)
  (name (string-ascii 100))
  (organization (optional (string-ascii 100)))
  (verification-level uint)
)
  (let (
    (current-id (var-get next-reporter-id))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    (asserts! (is-none (map-get? reporter-principals { principal: reporter-principal })) ERR-INCIDENT-ALREADY-EXISTS)
    
    ;; Register reporter
    (map-set reporters
      { reporter-id: current-id }
      {
        principal: reporter-principal,
        name: name,
        organization: organization,
        verification-level: verification-level,
        registration-date: stacks-block-height,
        total-reports: u0,
        accuracy-score: u100
      }
    )
    
    ;; Create principal lookup
    (map-set reporter-principals
      { principal: reporter-principal }
      { reporter-id: current-id }
    )
    
    ;; Increment reporter ID
    (var-set next-reporter-id (+ current-id u1))
    
    (ok current-id)
  )
)

;; Register a new auditor
(define-public (register-auditor
  (auditor-principal principal)
  (name (string-ascii 100))
  (certification (string-ascii 100))
  (specialization (string-ascii 50))
)
  (let (
    (current-id (var-get next-auditor-id))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    (asserts! (is-none (map-get? auditor-principals { principal: auditor-principal })) ERR-INCIDENT-ALREADY-EXISTS)
    
    ;; Register auditor
    (map-set auditors
      { auditor-id: current-id }
      {
        principal: auditor-principal,
        name: name,
        certification: certification,
        specialization: specialization,
        registration-date: stacks-block-height,
        total-cases: u0,
        success-rate: u0,
        active-status: true
      }
    )
    
    ;; Create principal lookup
    (map-set auditor-principals
      { principal: auditor-principal }
      { auditor-id: current-id }
    )
    
    ;; Increment auditor ID
    (var-set next-auditor-id (+ current-id u1))
    
    (ok current-id)
  )
)

;; Report a greenwashing incident
(define-public (report-incident
  (reported-entity (string-ascii 100))
  (entity-principal (optional principal))
  (claim-id (optional uint))
  (incident-type (string-ascii 50))
  (severity uint)
  (evidence-links (list 5 (string-ascii 200)))
  (description (string-ascii 500))
  (public-visibility bool)
)
  (let (
    (current-incident-id (var-get next-incident-id))
    (reporter-data (unwrap! (map-get? reporter-principals { principal: tx-sender }) ERR-NOT-AUTHORIZED))
    (reporter-id (get reporter-id reporter-data))
  )
    (asserts! (validate-severity severity) ERR-INVALID-SEVERITY)
    (asserts! (is-authorized-reporter tx-sender) ERR-NOT-AUTHORIZED)
    
    ;; Create incident report
    (map-set incidents
      { incident-id: current-incident-id }
      {
        reporter-id: reporter-id,
        reported-entity: reported-entity,
        entity-principal: entity-principal,
        claim-id: claim-id,
        incident-type: incident-type,
        severity: severity,
        report-date: stacks-block-height,
        status: STATUS-REPORTED,
        assigned-auditor: none,
        evidence-links: evidence-links,
        description: description,
        public-visibility: public-visibility
      }
    )
    
    ;; Update reporter's total reports
    (match (map-get? reporters { reporter-id: reporter-id })
      reporter-info
        (map-set reporters
          { reporter-id: reporter-id }
          (merge reporter-info { total-reports: (+ (get total-reports reporter-info) u1) })
        )
      false
    )
    
    ;; Increment incident ID
    (var-set next-incident-id (+ current-incident-id u1))
    
    (ok current-incident-id)
  )
)

;; Assign auditor to incident
(define-public (assign-auditor (incident-id uint) (auditor-id uint))
  (let (
    (incident-data (unwrap! (map-get? incidents { incident-id: incident-id }) ERR-INCIDENT-NOT-FOUND))
    (auditor-data (unwrap! (map-get? auditors { auditor-id: auditor-id }) ERR-AUDITOR-NOT-FOUND))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    (asserts! (get active-status auditor-data) ERR-NOT-AUTHORIZED)
    
    ;; Assign auditor and update status
    (map-set incidents
      { incident-id: incident-id }
      (merge incident-data {
        assigned-auditor: (some auditor-id),
        status: STATUS-UNDER-REVIEW
      })
    )
    
    ;; Update auditor's total cases
    (map-set auditors
      { auditor-id: auditor-id }
      (merge auditor-data { total-cases: (+ (get total-cases auditor-data) u1) })
    )
    
    (ok true)
  )
)

;; Add investigation log entry
(define-public (add-investigation-log
  (incident-id uint)
  (action-type (string-ascii 50))
  (notes (string-ascii 300))
  (evidence-collected bool)
)
  (let (
    (incident-data (unwrap! (map-get? incidents { incident-id: incident-id }) ERR-INCIDENT-NOT-FOUND))
    (auditor-data (unwrap! (map-get? auditor-principals { principal: tx-sender }) ERR-NOT-AUTHORIZED))
    (auditor-id (get auditor-id auditor-data))
    (log-entry u1) ;; Simplified - would need counter per incident
  )
    (asserts! (is-authorized-auditor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get assigned-auditor incident-data) (some auditor-id)) ERR-NOT-AUTHORIZED)
    
    ;; Add log entry
    (map-set investigation-logs
      { incident-id: incident-id, log-entry: log-entry }
      {
        auditor-id: auditor-id,
        entry-date: stacks-block-height,
        action-type: action-type,
        notes: notes,
        evidence-collected: evidence-collected
      }
    )
    
    (ok true)
  )
)

;; Resolve incident
(define-public (resolve-incident
  (incident-id uint)
  (final-status (string-ascii 20))
  (evidence-score uint)
  (corrective-actions (string-ascii 500))
  (follow-up-required bool)
  (public-report (string-ascii 1000))
)
  (let (
    (current-resolution-id (var-get next-resolution-id))
    (incident-data (unwrap! (map-get? incidents { incident-id: incident-id }) ERR-INCIDENT-NOT-FOUND))
    (auditor-data (unwrap! (map-get? auditor-principals { principal: tx-sender }) ERR-NOT-AUTHORIZED))
    (auditor-id (get auditor-id auditor-data))
    (penalty (calculate-penalty (get severity incident-data) evidence-score))
  )
    (asserts! (is-authorized-auditor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get assigned-auditor incident-data) (some auditor-id)) ERR-NOT-AUTHORIZED)
    (asserts! (<= evidence-score u100) ERR-INVALID-SEVERITY)
    
    ;; Create resolution record
    (map-set resolutions
      { resolution-id: current-resolution-id }
      {
        incident-id: incident-id,
        auditor-id: auditor-id,
        resolution-date: stacks-block-height,
        final-status: final-status,
        evidence-score: evidence-score,
        penalty-amount: penalty,
        corrective-actions: corrective-actions,
        follow-up-required: follow-up-required,
        public-report: public-report
      }
    )
    
    ;; Update incident status
    (map-set incidents
      { incident-id: incident-id }
      (merge incident-data { status: STATUS-RESOLVED })
    )
    
    ;; Update auditor success rate (simplified calculation)
    (let (
      (current-auditor-data (unwrap! (map-get? auditors { auditor-id: auditor-id }) ERR-AUDITOR-NOT-FOUND))
      (new-success-rate (if (is-eq final-status STATUS-VERIFIED) 
                          (+ (get success-rate current-auditor-data) u10)
                          (get success-rate current-auditor-data)))
    )
      (map-set auditors
        { auditor-id: auditor-id }
        (merge current-auditor-data { success-rate: new-success-rate })
      )
    )
    
    ;; Increment resolution ID
    (var-set next-resolution-id (+ current-resolution-id u1))
    
    (ok current-resolution-id)
  )
)

;; Update auditor status
(define-public (update-auditor-status (auditor-id uint) (active-status bool))
  (let (
    (auditor-data (unwrap! (map-get? auditors { auditor-id: auditor-id }) ERR-AUDITOR-NOT-FOUND))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    
    (map-set auditors
      { auditor-id: auditor-id }
      (merge auditor-data { active-status: active-status })
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-incident (incident-id uint))
  (map-get? incidents { incident-id: incident-id })
)

(define-read-only (get-reporter (reporter-id uint))
  (map-get? reporters { reporter-id: reporter-id })
)

(define-read-only (get-auditor (auditor-id uint))
  (map-get? auditors { auditor-id: auditor-id })
)

(define-read-only (get-resolution (resolution-id uint))
  (map-get? resolutions { resolution-id: resolution-id })
)

(define-read-only (get-investigation-log (incident-id uint) (log-entry uint))
  (map-get? investigation-logs { incident-id: incident-id, log-entry: log-entry })
)

(define-read-only (get-reporter-by-principal (reporter-principal principal))
  (match (map-get? reporter-principals { principal: reporter-principal })
    reporter-data (map-get? reporters { reporter-id: (get reporter-id reporter-data) })
    none
  )
)

(define-read-only (get-auditor-by-principal (auditor-principal principal))
  (match (map-get? auditor-principals { principal: auditor-principal })
    auditor-data (map-get? auditors { auditor-id: (get auditor-id auditor-data) })
    none
  )
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (get-next-ids)
  {
    next-incident-id: (var-get next-incident-id),
    next-reporter-id: (var-get next-reporter-id),
    next-auditor-id: (var-get next-auditor-id),
    next-resolution-id: (var-get next-resolution-id)
  }
)

;; Get public incidents for transparency reporting
(define-read-only (get-public-incident-count)
  ;; Simplified - would need iteration over incidents
  ;; Returns next-incident-id as approximation
  (var-get next-incident-id)
)

