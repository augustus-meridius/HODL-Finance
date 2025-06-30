;; HODL Finance - STX Lending with Bitcoin Collateral
;; A decentralized lending protocol on Stacks leveraging Bitcoin as collateral

;; Contract constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u101))
(define-constant ERR_LOAN_NOT_FOUND (err u102))
(define-constant ERR_LOAN_EXPIRED (err u103))
(define-constant ERR_ALREADY_LIQUIDATED (err u104))
(define-constant ERR_INSUFFICIENT_FUNDS (err u105))
(define-constant ERR_INVALID_AMOUNT (err u106))
(define-constant ERR_COLLATERAL_LOCKED (err u107))
(define-constant ERR_REPAYMENT_FAILED (err u108))

;; Protocol parameters
(define-constant COLLATERAL_RATIO u150) ;; 150% collateralization required
(define-constant LIQUIDATION_THRESHOLD u125) ;; Liquidate at 125%
(define-constant INTEREST_RATE u500) ;; 5% annual interest (basis points)
(define-constant LIQUIDATION_PENALTY u1000) ;; 10% liquidation penalty
(define-constant MAX_LOAN_DURATION u52560000) ;; ~1 year in blocks

;; Data variables
(define-data-var total-stx-lent uint u0)
(define-data-var total-btc-collateral uint u0)
(define-data-var loan-id-nonce uint u0)
(define-data-var btc-stx-price uint u100000) ;; Price in micro-STX per satoshi
(define-data-var protocol-fee-rate uint u100) ;; 1% protocol fee

;; Data maps
(define-map loans
  { loan-id: uint }
  {
    borrower: principal,
    stx-amount: uint,
    btc-collateral: uint,
    interest-rate: uint,
    start-block: uint,
    duration-blocks: uint,
    is-active: bool,
    collateral-locked: bool
  }
)

(define-map user-loans
  { user: principal }
  { loan-ids: (list 50 uint) }
)

(define-map btc-deposits
  { user: principal, tx-hash: (buff 32) }
  {
    amount: uint,
    block-height: uint,
    is-locked: bool,
    associated-loan: (optional uint)
  }
)

(define-map liquidation-queue
  { loan-id: uint }
  { liquidator: principal, liquidation-block: uint }
)

;; Protocol treasury
(define-data-var protocol-treasury uint u0)

;; Read-only functions

(define-read-only (get-loan (loan-id uint))
  (map-get? loans { loan-id: loan-id })
)

(define-read-only (get-user-loans (user principal))
  (default-to { loan-ids: (list) } (map-get? user-loans { user: user }))
)

(define-read-only (get-btc-deposit (user principal) (tx-hash (buff 32)))
  (map-get? btc-deposits { user: user, tx-hash: tx-hash })
)

(define-read-only (calculate-interest (principal-amount uint) (rate uint) (blocks uint))
  (let ((annual-blocks u52560000)) ;; Approximate blocks per year
    (/ (* (* principal-amount rate) blocks) (* annual-blocks u10000))
  )
)

(define-read-only (get-loan-health (loan-id uint))
  (match (get-loan loan-id)
    loan-data
    (let (
      (stx-value (get stx-amount loan-data))
      (btc-value (* (get btc-collateral loan-data) (var-get btc-stx-price)))
      (collateral-ratio-current (if (> stx-value u0) (/ (* btc-value u100) stx-value) u0))
    )
    (ok {
      collateral-ratio: collateral-ratio-current,
      is-healthy: (>= collateral-ratio-current LIQUIDATION_THRESHOLD),
      stx-debt: stx-value,
      btc-collateral-value: btc-value
    }))
    ERR_LOAN_NOT_FOUND
  )
)

(define-read-only (get-protocol-stats)
  {
    total-stx-lent: (var-get total-stx-lent),
    total-btc-collateral: (var-get total-btc-collateral),
    active-loans: (var-get loan-id-nonce),
    btc-stx-price: (var-get btc-stx-price),
    protocol-treasury: (var-get protocol-treasury)
  }
)

;; Administrative functions

(define-public (set-btc-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-price u0) ERR_INVALID_AMOUNT)
    (var-set btc-stx-price new-price)
    (ok true)
  )
)

(define-public (update-protocol-fee (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_AMOUNT) ;; Max 10%
    (var-set protocol-fee-rate new-rate)
    (ok true)
  )
)

;; Core lending functions

(define-public (register-btc-collateral (tx-hash (buff 32)) (amount uint) (proof (buff 1024)))
  (let (
    (deposit-key { user: tx-sender, tx-hash: tx-hash })
  )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (is-none (map-get? btc-deposits deposit-key)) ERR_COLLATERAL_LOCKED)
    
    ;; In a production environment, you would verify the Bitcoin transaction proof here
    ;; using Stacks' Bitcoin integration capabilities
    
    (map-set btc-deposits deposit-key {
      amount: amount,
      block-height: block-height,
      is-locked: false,
      associated-loan: none
    })
    (var-set total-btc-collateral (+ (var-get total-btc-collateral) amount))
    (ok tx-hash)
  )
)

(define-public (create-loan (btc-tx-hash (buff 32)) (stx-amount uint) (duration-blocks uint))
  (let (
    (loan-id (+ (var-get loan-id-nonce) u1))
    (deposit-key { user: tx-sender, tx-hash: btc-tx-hash })
    (btc-deposit (unwrap! (map-get? btc-deposits deposit-key) ERR_INSUFFICIENT_COLLATERAL))
    (btc-collateral (get amount btc-deposit))
    (collateral-value (* btc-collateral (var-get btc-stx-price)))
    (required-collateral (/ (* stx-amount COLLATERAL_RATIO) u100))
    (current-user-loans (get loan-ids (get-user-loans tx-sender)))
  )
    (asserts! (> stx-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= duration-blocks MAX_LOAN_DURATION) ERR_INVALID_AMOUNT)
    (asserts! (not (get is-locked btc-deposit)) ERR_COLLATERAL_LOCKED)
    (asserts! (>= collateral-value required-collateral) ERR_INSUFFICIENT_COLLATERAL)
    (asserts! (>= (stx-get-balance (as-contract tx-sender)) stx-amount) ERR_INSUFFICIENT_FUNDS)
    
    ;; Lock the collateral
    (map-set btc-deposits deposit-key (merge btc-deposit {
      is-locked: true,
      associated-loan: (some loan-id)
    }))
    
    ;; Create the loan
    (map-set loans { loan-id: loan-id } {
      borrower: tx-sender,
      stx-amount: stx-amount,
      btc-collateral: btc-collateral,
      interest-rate: INTEREST_RATE,
      start-block: block-height,
      duration-blocks: duration-blocks,
      is-active: true,
      collateral-locked: true
    })
    
    ;; Update user loans tracking
    (map-set user-loans { user: tx-sender } {
      loan-ids: (unwrap! (as-max-len? (append current-user-loans loan-id) u50) ERR_INVALID_AMOUNT)
    })
    
    ;; Transfer STX to borrower
    (try! (as-contract (stx-transfer? stx-amount tx-sender tx-sender)))
    
    ;; Update protocol state
    (var-set loan-id-nonce loan-id)
    (var-set total-stx-lent (+ (var-get total-stx-lent) stx-amount))
    
    (ok loan-id)
  )
)

(define-public (repay-loan (loan-id uint))
  (let (
    (loan-data (unwrap! (get-loan loan-id) ERR_LOAN_NOT_FOUND))
    (borrower (get borrower loan-data))
    (principal-amount (get stx-amount loan-data))
    (blocks-elapsed (- block-height (get start-block loan-data)))
    (interest-amount (calculate-interest principal-amount (get interest-rate loan-data) blocks-elapsed))
    (protocol-fee (/ (* interest-amount (var-get protocol-fee-rate)) u10000))
    (total-repayment (+ principal-amount interest-amount))
    (btc-collateral (get btc-collateral loan-data))
  )
    (asserts! (is-eq tx-sender borrower) ERR_UNAUTHORIZED)
    (asserts! (get is-active loan-data) ERR_LOAN_NOT_FOUND)
    (asserts! (>= (stx-get-balance tx-sender) total-repayment) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer repayment
    (try! (stx-transfer? total-repayment tx-sender (as-contract tx-sender)))
    
    ;; Update protocol treasury
    (var-set protocol-treasury (+ (var-get protocol-treasury) protocol-fee))
    
    ;; Deactivate loan
    (map-set loans { loan-id: loan-id } (merge loan-data {
      is-active: false,
      collateral-locked: false
    }))
    
    ;; Unlock collateral (simplified - in production would need Bitcoin transaction handling)
    ;; Update protocol state
    (var-set total-stx-lent (- (var-get total-stx-lent) principal-amount))
    (var-set total-btc-collateral (- (var-get total-btc-collateral) btc-collateral))
    
    (ok { repaid: total-repayment, interest: interest-amount, fee: protocol-fee })
  )
)

(define-public (liquidate-loan (loan-id uint))
  (let (
    (loan-data (unwrap! (get-loan loan-id) ERR_LOAN_NOT_FOUND))
    (health-data (unwrap! (get-loan-health loan-id) ERR_LOAN_NOT_FOUND))
    (stx-debt (get stx-debt health-data))
    (liquidation-bonus (/ (* stx-debt LIQUIDATION_PENALTY) u10000))
    (total-liquidation-cost (+ stx-debt liquidation-bonus))
  )
    (asserts! (get is-active loan-data) ERR_LOAN_NOT_FOUND)
    (asserts! (not (get is-healthy health-data)) ERR_INSUFFICIENT_COLLATERAL)
    (asserts! (>= (stx-get-balance tx-sender) total-liquidation-cost) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer liquidation payment
    (try! (stx-transfer? total-liquidation-cost tx-sender (as-contract tx-sender)))
    
    ;; Deactivate loan
    (map-set loans { loan-id: loan-id } (merge loan-data {
      is-active: false,
      collateral-locked: false
    }))
    
    ;; Record liquidation
    (map-set liquidation-queue { loan-id: loan-id } {
      liquidator: tx-sender,
      liquidation-block: block-height
    })
    
    ;; Update protocol state
    (var-set total-stx-lent (- (var-get total-stx-lent) (get stx-amount loan-data)))
    (var-set total-btc-collateral (- (var-get total-btc-collateral) (get btc-collateral loan-data)))
    (var-set protocol-treasury (+ (var-get protocol-treasury) liquidation-bonus))
    
    (ok { liquidated-debt: stx-debt, bonus: liquidation-bonus, btc-collateral: (get btc-collateral loan-data) })
  )
)

;; Emergency functions

(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; Emergency pause logic would be implemented here
    (ok true)
  )
)

(define-public (withdraw-protocol-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= amount (var-get protocol-treasury)) ERR_INSUFFICIENT_FUNDS)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
    (var-set protocol-treasury (- (var-get protocol-treasury) amount))
    (ok amount)
  )
)

;; Initialize contract
(begin
  (var-set loan-id-nonce u0)
  (var-set total-stx-lent u0)
  (var-set total-btc-collateral u0)
)