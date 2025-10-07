;; eco-incentive-rewards
;; Token rebates for high PCR usage and audited transparency

;; constants
(define-constant ERR-OWNER-ONLY (err u400))
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-PARTICIPANT-NOT-FOUND (err u402))
(define-constant ERR-PROGRAM-NOT-FOUND (err u403))
(define-constant ERR-INSUFFICIENT-BALANCE (err u404))
(define-constant ERR-REWARD-NOT-FOUND (err u405))
(define-constant ERR-ALREADY-CLAIMED (err u406))
(define-constant ERR-PROGRAM-INACTIVE (err u407))
(define-constant ERR-INVALID-AMOUNT (err u408))
(define-constant ERR-QUALIFICATION-FAILED (err u409))

;; Reward program types
(define-constant PROGRAM-PCR-USAGE "pcr-usage")
(define-constant PROGRAM-TRANSPARENCY "transparency")
(define-constant PROGRAM-AUDIT-COMPLIANCE "audit-compliance")
(define-constant PROGRAM-INNOVATION "innovation")

;; Qualification tiers
(define-constant TIER-BRONZE u1)
(define-constant TIER-SILVER u2)
(define-constant TIER-GOLD u3)
(define-constant TIER-PLATINUM u4)

;; data vars
(define-data-var contract-owner principal tx-sender)
(define-data-var next-participant-id uint u1)
(define-data-var next-program-id uint u1)
(define-data-var next-reward-id uint u1)
(define-data-var total-tokens-issued uint u0)
(define-data-var total-tokens-distributed uint u0)

;; Participant registry
(define-map participants
  { participant-id: uint }
  {
    principal: principal,
    name: (string-ascii 100),
    organization-type: (string-ascii 50),
    registration-date: uint,
    qualification-tier: uint,
    total-earned: uint,
    total-claimed: uint,
    active-status: bool
  }
)

;; Reward programs
(define-map reward-programs
  {
    program-id: uint
  }
  {
    name: (string-ascii 100),
    program-type: (string-ascii 50),
    description: (string-ascii 300),
    reward-rate: uint,
    minimum-threshold: uint,
    maximum-reward: uint,
    start-date: uint,
    end-date: (optional uint),
    active-status: bool,
    total-allocated: uint,
    total-distributed: uint
  }
)

;; Individual rewards
(define-map rewards
  {
    reward-id: uint
  }
  {
    participant-id: uint,
    program-id: uint,
    pcr-percentage: uint,
    biobased-percentage: uint,
    transparency-score: uint,
    audit-score: uint,
    earned-date: uint,
    reward-amount: uint,
    claimed-status: bool,
    claimed-date: (optional uint),
    evidence-hash: (string-ascii 64)
  }
)

;; Token balances
(define-map token-balances
  { participant: principal }
  { balance: uint }
)

;; Program statistics
(define-map program-stats
  {
    program-id: uint,
    period: uint
  }
  {
    participants-count: uint,
    total-rewards: uint,
    average-pcr: uint,
    top-performer: (optional uint)
  }
)

;; Principal lookups
(define-map participant-principals
  { principal: principal }
  { participant-id: uint }
)

;; private functions
(define-private (is-contract-owner (caller principal))
  (is-eq caller (var-get contract-owner))
)

(define-private (is-authorized-participant (caller principal))
  (match (map-get? participant-principals { principal: caller })
    participant-data
      (match (map-get? participants { participant-id: (get participant-id participant-data) })
        participant-info (get active-status participant-info)
        false
      )
    false
  )
)

(define-private (calculate-pcr-reward (pcr-percentage uint) (reward-rate uint))
  (/ (* pcr-percentage reward-rate) u100)
)

(define-private (calculate-transparency-bonus (transparency-score uint) (base-reward uint))
  (if (>= transparency-score u80)
    (/ (* base-reward u20) u100)
    u0
  )
)

(define-private (calculate-audit-multiplier (audit-score uint))
  (if (>= audit-score u90)
    u150
    (if (>= audit-score u70)
      u120
      u100
    )
  )
)

(define-private (get-tier-multiplier (tier uint))
  (if (is-eq tier TIER-PLATINUM)
    u200
    (if (is-eq tier TIER-GOLD)
      u150
      (if (is-eq tier TIER-SILVER)
        u120
        u100
      )
    )
  )
)

(define-private (min-uint (a uint) (b uint))
  (if (<= a b) a b)
)

;; public functions

;; Register a participant
(define-public (register-participant
  (participant-principal principal)
  (name (string-ascii 100))
  (organization-type (string-ascii 50))
  (initial-tier uint)
)
  (let (
    (current-id (var-get next-participant-id))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    (asserts! (is-none (map-get? participant-principals { principal: participant-principal })) ERR-PARTICIPANT-NOT-FOUND)
    (asserts! (and (>= initial-tier TIER-BRONZE) (<= initial-tier TIER-PLATINUM)) ERR-INVALID-AMOUNT)
    
    ;; Register participant
    (map-set participants
      { participant-id: current-id }
      {
        principal: participant-principal,
        name: name,
        organization-type: organization-type,
        registration-date: stacks-block-height,
        qualification-tier: initial-tier,
        total-earned: u0,
        total-claimed: u0,
        active-status: true
      }
    )
    
    ;; Create principal lookup
    (map-set participant-principals
      { principal: participant-principal }
      { participant-id: current-id }
    )
    
    ;; Initialize token balance
    (map-set token-balances
      { participant: participant-principal }
      { balance: u0 }
    )
    
    ;; Increment participant ID
    (var-set next-participant-id (+ current-id u1))
    
    (ok current-id)
  )
)

;; Create reward program
(define-public (create-reward-program
  (name (string-ascii 100))
  (program-type (string-ascii 50))
  (description (string-ascii 300))
  (reward-rate uint)
  (minimum-threshold uint)
  (maximum-reward uint)
  (duration-blocks uint)
)
  (let (
    (current-id (var-get next-program-id))
    (end-date (if (> duration-blocks u0) (some (+ stacks-block-height duration-blocks)) none))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    (asserts! (> reward-rate u0) ERR-INVALID-AMOUNT)
    (asserts! (> maximum-reward u0) ERR-INVALID-AMOUNT)
    
    ;; Create program
    (map-set reward-programs
      { program-id: current-id }
      {
        name: name,
        program-type: program-type,
        description: description,
        reward-rate: reward-rate,
        minimum-threshold: minimum-threshold,
        maximum-reward: maximum-reward,
        start-date: stacks-block-height,
        end-date: end-date,
        active-status: true,
        total-allocated: u0,
        total-distributed: u0
      }
    )
    
    ;; Increment program ID
    (var-set next-program-id (+ current-id u1))
    
    (ok current-id)
  )
)

;; Calculate and award eco-rewards
(define-public (calculate-eco-reward
  (program-id uint)
  (pcr-percentage uint)
  (biobased-percentage uint)
  (transparency-score uint)
  (audit-score uint)
  (evidence-hash (string-ascii 64))
)
  (let (
    (current-reward-id (var-get next-reward-id))
    (participant-data (unwrap! (map-get? participant-principals { principal: tx-sender }) ERR-NOT-AUTHORIZED))
    (participant-id (get participant-id participant-data))
    (participant-info (unwrap! (map-get? participants { participant-id: participant-id }) ERR-PARTICIPANT-NOT-FOUND))
    (program-data (unwrap! (map-get? reward-programs { program-id: program-id }) ERR-PROGRAM-NOT-FOUND))
    (base-pcr-reward (calculate-pcr-reward pcr-percentage (get reward-rate program-data)))
    (transparency-bonus (calculate-transparency-bonus transparency-score base-pcr-reward))
    (audit-multiplier (calculate-audit-multiplier audit-score))
    (tier-multiplier (get-tier-multiplier (get qualification-tier participant-info)))
    (total-reward (min-uint 
                    (/ (* (+ base-pcr-reward transparency-bonus) audit-multiplier tier-multiplier) u10000)
                    (get maximum-reward program-data)))
  )
    (asserts! (is-authorized-participant tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get active-status program-data) ERR-PROGRAM-INACTIVE)
    (asserts! (>= (+ pcr-percentage biobased-percentage) (get minimum-threshold program-data)) ERR-QUALIFICATION-FAILED)
    (asserts! (<= pcr-percentage u100) ERR-INVALID-AMOUNT)
    (asserts! (<= biobased-percentage u100) ERR-INVALID-AMOUNT)
    (asserts! (<= transparency-score u100) ERR-INVALID-AMOUNT)
    (asserts! (<= audit-score u100) ERR-INVALID-AMOUNT)
    
    ;; Create reward record
    (map-set rewards
      { reward-id: current-reward-id }
      {
        participant-id: participant-id,
        program-id: program-id,
        pcr-percentage: pcr-percentage,
        biobased-percentage: biobased-percentage,
        transparency-score: transparency-score,
        audit-score: audit-score,
        earned-date: stacks-block-height,
        reward-amount: total-reward,
        claimed-status: false,
        claimed-date: none,
        evidence-hash: evidence-hash
      }
    )
    
    ;; Update participant total earned
    (map-set participants
      { participant-id: participant-id }
      (merge participant-info { total-earned: (+ (get total-earned participant-info) total-reward) })
    )
    
    ;; Update program statistics
    (match (map-get? reward-programs { program-id: program-id })
      current-program
        (map-set reward-programs
          { program-id: program-id }
          (merge current-program { total-allocated: (+ (get total-allocated current-program) total-reward) })
        )
      false
    )
    
    ;; Update global statistics
    (var-set total-tokens-issued (+ (var-get total-tokens-issued) total-reward))
    
    ;; Increment reward ID
    (var-set next-reward-id (+ current-reward-id u1))
    
    (ok { reward-id: current-reward-id, amount: total-reward })
  )
)

;; Claim reward tokens
(define-public (claim-reward (reward-id uint))
  (let (
    (reward-data (unwrap! (map-get? rewards { reward-id: reward-id }) ERR-REWARD-NOT-FOUND))
    (participant-data (unwrap! (map-get? participants { participant-id: (get participant-id reward-data) }) ERR-PARTICIPANT-NOT-FOUND))
    (reward-amount (get reward-amount reward-data))
    (current-balance (default-to u0 (get balance (map-get? token-balances { participant: tx-sender }))))
  )
    (asserts! (is-eq (get principal participant-data) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (get claimed-status reward-data)) ERR-ALREADY-CLAIMED)
    (asserts! (> reward-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update reward as claimed
    (map-set rewards
      { reward-id: reward-id }
      (merge reward-data {
        claimed-status: true,
        claimed-date: (some stacks-block-height)
      })
    )
    
    ;; Update participant balance
    (map-set token-balances
      { participant: tx-sender }
      { balance: (+ current-balance reward-amount) }
    )
    
    ;; Update participant total claimed
    (map-set participants
      { participant-id: (get participant-id reward-data) }
      (merge participant-data { total-claimed: (+ (get total-claimed participant-data) reward-amount) })
    )
    
    ;; Update global distribution statistics
    (var-set total-tokens-distributed (+ (var-get total-tokens-distributed) reward-amount))
    
    (ok reward-amount)
  )
)

;; Transfer tokens between participants
(define-public (transfer-tokens (recipient principal) (amount uint))
  (let (
    (sender-balance (default-to u0 (get balance (map-get? token-balances { participant: tx-sender }))))
    (recipient-balance (default-to u0 (get balance (map-get? token-balances { participant: recipient }))))
  )
    (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-authorized-participant tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-authorized-participant recipient) ERR-NOT-AUTHORIZED)
    
    ;; Update sender balance
    (map-set token-balances
      { participant: tx-sender }
      { balance: (- sender-balance amount) }
    )
    
    ;; Update recipient balance
    (map-set token-balances
      { participant: recipient }
      { balance: (+ recipient-balance amount) }
    )
    
    (ok true)
  )
)

;; Update participant tier
(define-public (update-participant-tier (participant-id uint) (new-tier uint))
  (let (
    (participant-data (unwrap! (map-get? participants { participant-id: participant-id }) ERR-PARTICIPANT-NOT-FOUND))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    (asserts! (and (>= new-tier TIER-BRONZE) (<= new-tier TIER-PLATINUM)) ERR-INVALID-AMOUNT)
    
    (map-set participants
      { participant-id: participant-id }
      (merge participant-data { qualification-tier: new-tier })
    )
    
    (ok true)
  )
)

;; Deactivate reward program
(define-public (deactivate-program (program-id uint))
  (let (
    (program-data (unwrap! (map-get? reward-programs { program-id: program-id }) ERR-PROGRAM-NOT-FOUND))
  )
    (asserts! (is-contract-owner tx-sender) ERR-OWNER-ONLY)
    
    (map-set reward-programs
      { program-id: program-id }
      (merge program-data { active-status: false })
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-participant (participant-id uint))
  (map-get? participants { participant-id: participant-id })
)

(define-read-only (get-participant-by-principal (participant-principal principal))
  (match (map-get? participant-principals { principal: participant-principal })
    participant-data (map-get? participants { participant-id: (get participant-id participant-data) })
    none
  )
)

(define-read-only (get-reward-program (program-id uint))
  (map-get? reward-programs { program-id: program-id })
)

(define-read-only (get-reward (reward-id uint))
  (map-get? rewards { reward-id: reward-id })
)

(define-read-only (get-token-balance (participant principal))
  (default-to u0 (get balance (map-get? token-balances { participant: participant })))
)

(define-read-only (get-program-stats (program-id uint) (period uint))
  (map-get? program-stats { program-id: program-id, period: period })
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (get-global-statistics)
  {
    total-participants: (var-get next-participant-id),
    total-programs: (var-get next-program-id),
    total-rewards: (var-get next-reward-id),
    total-tokens-issued: (var-get total-tokens-issued),
    total-tokens-distributed: (var-get total-tokens-distributed)
  }
)

;; Calculate potential reward preview
(define-read-only (preview-reward-calculation
  (program-id uint)
  (participant-principal principal)
  (pcr-percentage uint)
  (biobased-percentage uint)
  (transparency-score uint)
  (audit-score uint)
)
  (match (map-get? participant-principals { principal: participant-principal })
    participant-data
      (match (map-get? participants { participant-id: (get participant-id participant-data) })
        participant-info
          (match (map-get? reward-programs { program-id: program-id })
            program-data
              (let (
                (base-pcr-reward (calculate-pcr-reward pcr-percentage (get reward-rate program-data)))
                (transparency-bonus (calculate-transparency-bonus transparency-score base-pcr-reward))
                (audit-multiplier (calculate-audit-multiplier audit-score))
                (tier-multiplier (get-tier-multiplier (get qualification-tier participant-info)))
                (total-reward (min-uint 
                                (/ (* (+ base-pcr-reward transparency-bonus) audit-multiplier tier-multiplier) u10000)
                                (get maximum-reward program-data)))
              )
                (some {
                  base-reward: base-pcr-reward,
                  transparency-bonus: transparency-bonus,
                  audit-multiplier: audit-multiplier,
                  tier-multiplier: tier-multiplier,
                  total-reward: total-reward
                })
              )
            none
          )
        none
      )
    none
  )
)

