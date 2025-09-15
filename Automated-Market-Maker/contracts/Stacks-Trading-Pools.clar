;; Financial Pool Protocol - Multi-Asset DeFi Exchange Protocol
;; A comprehensive DeFi exchange protocol with AMM functionality, configurable bonding curves, 
;; time-locked staking, and multi-token liquidity pools

;; Error constants
(define-constant ERR-UNAUTHORIZED-ACCESS (err u1000))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1001))
(define-constant ERR-INVALID-AMOUNT (err u1002))
(define-constant ERR-POOL-NOT-EXISTS (err u1003))
(define-constant ERR-POOL-ALREADY-EXISTS (err u1004))
(define-constant ERR-SLIPPAGE-EXCEEDED (err u1005))
(define-constant ERR-INSUFFICIENT-LIQUIDITY (err u1006))
(define-constant ERR-INVALID-TOKEN-PAIR (err u1007))
(define-constant ERR-STAKING-PERIOD-NOT-ENDED (err u1008))
(define-constant ERR-NO-STAKE-FOUND (err u1009))
(define-constant ERR-INVALID-CURVE-PARAMETERS (err u1010))
(define-constant ERR-ZERO-LIQUIDITY (err u1011))
(define-constant ERR-INVALID-FEE-RATE (err u1012))
(define-constant ERR-PAUSED-PROTOCOL (err u1013))
(define-constant ERR-INVALID-POOL-ID (err u1014))
(define-constant ERR-DEADLINE-EXCEEDED (err u1015))

;; Protocol constants
(define-constant contract-owner tx-sender)
(define-constant max-fee-rate u10000)
(define-constant min-liquidity u1000)
(define-constant max-pools u1000)
(define-constant staking-reward-rate u500)
(define-constant curve-precision u1000000)

;; Protocol state
(define-data-var protocol-paused bool false)
(define-data-var pool-count uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var protocol-fee-rate uint u30)

;; Pool data structure
(define-map pools
  { pool-id: uint }
  {
    token-a: principal,
    token-b: principal,
    reserve-a: uint,
    reserve-b: uint,
    total-lp-tokens: uint,
    fee-rate: uint,
    curve-type: (string-ascii 10),
    curve-param-a: uint,
    curve-param-b: uint,
    created-at: uint,
    is-active: bool
  }
)

;; Liquidity provider positions
(define-map liquidity-positions
  { provider: principal, pool-id: uint }
  {
    lp-tokens: uint,
    last-deposit-block: uint,
    rewards-earned: uint
  }
)

;; Staking positions
(define-map staking-positions
  { staker: principal, stake-id: uint }
  {
    amount: uint,
    token: principal,
    locked-until: uint,
    reward-rate: uint,
    created-at: uint
  }
)

;; User stake counter
(define-map user-stake-count
  { user: principal }
  { count: uint }
)

;; Pool token balances
(define-map pool-token-balances
  { pool-id: uint, token: principal }
  { balance: uint }
)

;; Trading pairs registry
(define-map trading-pairs
  { token-a: principal, token-b: principal }
  { pool-id: uint, is-active: bool }
)

;; Fee collection tracking
(define-map collected-fees
  { token: principal }
  { amount: uint }
)

;; Private helper functions
(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (get-next-pool-id)
  (+ (var-get pool-count) u1)
)

(define-private (get-next-stake-id (user principal))
  (+ (default-to u0 (get count (map-get? user-stake-count { user: user }))) u1)
)

(define-private (sqrt (n uint))
  (if (<= n u1)
    n
    (let (
      (x0 n)
      (x1 (/ (+ n u1) u2))
      (x2 (/ (+ x1 (/ n x1)) u2))
      (x3 (/ (+ x2 (/ n x2)) u2))
      (x4 (/ (+ x3 (/ n x3)) u2))
      (x5 (/ (+ x4 (/ n x4)) u2))
      (x6 (/ (+ x5 (/ n x5)) u2))
      (x7 (/ (+ x6 (/ n x6)) u2))
      (x8 (/ (+ x7 (/ n x7)) u2))
      (x9 (/ (+ x8 (/ n x8)) u2))
      (x10 (/ (+ x9 (/ n x9)) u2))
    )
      x10
    )
  )
)

(define-private (calculate-constant-product-output (input-amount uint) (input-reserve uint) (output-reserve uint) (fee-rate uint))
  (let (
    (input-amount-with-fee (- input-amount (/ (* input-amount fee-rate) u10000)))
    (numerator (* input-amount-with-fee output-reserve))
    (denominator (+ input-reserve input-amount-with-fee))
  )
    (/ numerator denominator)
  )
)

(define-private (calculate-bonding-curve-output (input-amount uint) (curve-type (string-ascii 10)) (param-a uint) (param-b uint) (current-supply uint))
  (if (is-eq curve-type "linear")
    (/ (* input-amount param-a) curve-precision)
    (if (is-eq curve-type "exponential")
      (let ((base-price (/ (* current-supply param-a) curve-precision)))
        (/ (* input-amount (+ base-price param-b)) curve-precision)
      )
      (/ (* input-amount param-a) curve-precision)
    )
  )
)

(define-private (validate-slippage (expected-output uint) (actual-output uint) (max-slippage uint))
  (let ((slippage (if (> expected-output actual-output)
                   (/ (* (- expected-output actual-output) u10000) expected-output)
                   u0)))
    (<= slippage max-slippage)
  )
)

(define-private (update-pool-reserves (pool-id uint) (new-reserve-a uint) (new-reserve-b uint))
  (match (map-get? pools { pool-id: pool-id })
    pool-data
    (ok (map-set pools
      { pool-id: pool-id }
      (merge pool-data {
        reserve-a: new-reserve-a,
        reserve-b: new-reserve-b
      })
    ))
    ERR-POOL-NOT-EXISTS
  )
)

;; Public functions

;; Protocol management
(define-public (pause-protocol)
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (ok (var-set protocol-paused true))
  )
)

(define-public (unpause-protocol)
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (ok (var-set protocol-paused false))
  )
)

(define-public (set-protocol-fee-rate (new-rate uint))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (<= new-rate max-fee-rate) ERR-INVALID-FEE-RATE)
    (ok (var-set protocol-fee-rate new-rate))
  )
)

;; Pool creation and management
(define-public (create-pool 
  (token-a principal) 
  (token-b principal) 
  (initial-a uint) 
  (initial-b uint) 
  (fee-rate uint)
  (curve-type (string-ascii 10))
  (curve-param-a uint)
  (curve-param-b uint)
)
  (let (
    (pool-id (get-next-pool-id))
    (lp-tokens (sqrt (* initial-a initial-b)))
  )
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED-PROTOCOL)
    (asserts! (not (is-eq token-a token-b)) ERR-INVALID-TOKEN-PAIR)
    (asserts! (and (> initial-a u0) (> initial-b u0)) ERR-INVALID-AMOUNT)
    (asserts! (<= fee-rate max-fee-rate) ERR-INVALID-FEE-RATE)
    (asserts! (< (var-get pool-count) max-pools) ERR-INVALID-POOL-ID)
    (asserts! (is-none (map-get? trading-pairs { token-a: token-a, token-b: token-b })) ERR-POOL-ALREADY-EXISTS)
    (asserts! (is-none (map-get? trading-pairs { token-a: token-b, token-b: token-a })) ERR-POOL-ALREADY-EXISTS)
    (asserts! (>= lp-tokens min-liquidity) ERR-ZERO-LIQUIDITY)

    (try! (stx-transfer? initial-a tx-sender (as-contract tx-sender)))
    (try! (stx-transfer? initial-b tx-sender (as-contract tx-sender)))

    (map-set pools
      { pool-id: pool-id }
      {
        token-a: token-a,
        token-b: token-b,
        reserve-a: initial-a,
        reserve-b: initial-b,
        total-lp-tokens: lp-tokens,
        fee-rate: fee-rate,
        curve-type: curve-type,
        curve-param-a: curve-param-a,
        curve-param-b: curve-param-b,
        created-at: block-height,
        is-active: true
      }
    )

    (map-set liquidity-positions
      { provider: tx-sender, pool-id: pool-id }
      {
        lp-tokens: lp-tokens,
        last-deposit-block: block-height,
        rewards-earned: u0
      }
    )

    (map-set trading-pairs
      { token-a: token-a, token-b: token-b }
      { pool-id: pool-id, is-active: true }
    )

    (var-set pool-count pool-id)
    (ok pool-id)
  )
)

;; Add liquidity to existing pool
(define-public (add-liquidity (pool-id uint) (amount-a uint) (amount-b uint) (min-lp-tokens uint))
  (let (
    (pool-data (unwrap! (map-get? pools { pool-id: pool-id }) ERR-POOL-NOT-EXISTS))
    (current-position (default-to 
      { lp-tokens: u0, last-deposit-block: u0, rewards-earned: u0 }
      (map-get? liquidity-positions { provider: tx-sender, pool-id: pool-id })
    ))
    (reserve-a (get reserve-a pool-data))
    (reserve-b (get reserve-b pool-data))
    (total-lp (get total-lp-tokens pool-data))
    (lp-tokens-a (/ (* amount-a total-lp) reserve-a))
    (lp-tokens-b (/ (* amount-b total-lp) reserve-b))
    (lp-tokens (if (< lp-tokens-a lp-tokens-b) lp-tokens-a lp-tokens-b))
  )
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED-PROTOCOL)
    (asserts! (get is-active pool-data) ERR-POOL-NOT-EXISTS)
    (asserts! (and (> amount-a u0) (> amount-b u0)) ERR-INVALID-AMOUNT)
    (asserts! (>= lp-tokens min-lp-tokens) ERR-SLIPPAGE-EXCEEDED)

    (try! (stx-transfer? amount-a tx-sender (as-contract tx-sender)))
    (try! (stx-transfer? amount-b tx-sender (as-contract tx-sender)))

    (try! (update-pool-reserves pool-id (+ reserve-a amount-a) (+ reserve-b amount-b)))

    (map-set pools
      { pool-id: pool-id }
      (merge pool-data { total-lp-tokens: (+ total-lp lp-tokens) })
    )

    (map-set liquidity-positions
      { provider: tx-sender, pool-id: pool-id }
      {
        lp-tokens: (+ (get lp-tokens current-position) lp-tokens),
        last-deposit-block: block-height,
        rewards-earned: (get rewards-earned current-position)
      }
    )

    (ok lp-tokens)
  )
)

;; Remove liquidity from pool
(define-public (remove-liquidity (pool-id uint) (lp-tokens uint) (min-amount-a uint) (min-amount-b uint))
  (let (
    (pool-data (unwrap! (map-get? pools { pool-id: pool-id }) ERR-POOL-NOT-EXISTS))
    (user-position (unwrap! (map-get? liquidity-positions { provider: tx-sender, pool-id: pool-id }) ERR-INSUFFICIENT-BALANCE))
    (reserve-a (get reserve-a pool-data))
    (reserve-b (get reserve-b pool-data))
    (total-lp (get total-lp-tokens pool-data))
    (amount-a (/ (* lp-tokens reserve-a) total-lp))
    (amount-b (/ (* lp-tokens reserve-b) total-lp))
  )
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED-PROTOCOL)
    (asserts! (> lp-tokens u0) ERR-INVALID-AMOUNT)
    (asserts! (<= lp-tokens (get lp-tokens user-position)) ERR-INSUFFICIENT-BALANCE)
    (asserts! (and (>= amount-a min-amount-a) (>= amount-b min-amount-b)) ERR-SLIPPAGE-EXCEEDED)

    (try! (as-contract (stx-transfer? amount-a tx-sender tx-sender)))
    (try! (as-contract (stx-transfer? amount-b tx-sender tx-sender)))

    (try! (update-pool-reserves pool-id (- reserve-a amount-a) (- reserve-b amount-b)))

    (map-set pools
      { pool-id: pool-id }
      (merge pool-data { total-lp-tokens: (- total-lp lp-tokens) })
    )

    (map-set liquidity-positions
      { provider: tx-sender, pool-id: pool-id }
      (merge user-position { lp-tokens: (- (get lp-tokens user-position) lp-tokens) })
    )

    (ok { amount-a: amount-a, amount-b: amount-b })
  )
)

;; Swap tokens
(define-public (swap-exact-tokens-for-tokens 
  (pool-id uint) 
  (token-in principal) 
  (amount-in uint) 
  (min-amount-out uint)
  (deadline uint)
)
  (let (
    (pool-data (unwrap! (map-get? pools { pool-id: pool-id }) ERR-POOL-NOT-EXISTS))
    (is-token-a (is-eq token-in (get token-a pool-data)))
    (reserve-in (if is-token-a (get reserve-a pool-data) (get reserve-b pool-data)))
    (reserve-out (if is-token-a (get reserve-b pool-data) (get reserve-a pool-data)))
    (amount-out (calculate-constant-product-output amount-in reserve-in reserve-out (get fee-rate pool-data)))
    (fee-amount (/ (* amount-in (get fee-rate pool-data)) u10000))
  )
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED-PROTOCOL)
    (asserts! (get is-active pool-data) ERR-POOL-NOT-EXISTS)
    (asserts! (<= block-height deadline) ERR-DEADLINE-EXCEEDED)
    (asserts! (> amount-in u0) ERR-INVALID-AMOUNT)
    (asserts! (>= amount-out min-amount-out) ERR-SLIPPAGE-EXCEEDED)
    (asserts! (or (is-eq token-in (get token-a pool-data)) (is-eq token-in (get token-b pool-data))) ERR-INVALID-TOKEN-PAIR)

    (try! (stx-transfer? amount-in tx-sender (as-contract tx-sender)))
    (try! (as-contract (stx-transfer? amount-out tx-sender tx-sender)))

    (if is-token-a
      (try! (update-pool-reserves pool-id (+ reserve-in amount-in) (- reserve-out amount-out)))
      (try! (update-pool-reserves pool-id (- reserve-out amount-out) (+ reserve-in amount-in)))
    )

    (var-set total-fees-collected (+ (var-get total-fees-collected) fee-amount))

    (ok amount-out)
  )
)

;; Staking functions
(define-public (stake-tokens (token principal) (amount uint) (lock-period uint))
  (let (
    (stake-id (get-next-stake-id tx-sender))
    (current-count (default-to u0 (get count (map-get? user-stake-count { user: tx-sender }))))
    (lock-until (+ block-height lock-period))
  )
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED-PROTOCOL)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> lock-period u0) ERR-INVALID-AMOUNT)

    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    (map-set staking-positions
      { staker: tx-sender, stake-id: stake-id }
      {
        amount: amount,
        token: token,
        locked-until: lock-until,
        reward-rate: staking-reward-rate,
        created-at: block-height
      }
    )

    (map-set user-stake-count
      { user: tx-sender }
      { count: (+ current-count u1) }
    )

    (ok stake-id)
  )
)

(define-public (unstake-tokens (stake-id uint))
  (let (
    (stake-data (unwrap! (map-get? staking-positions { staker: tx-sender, stake-id: stake-id }) ERR-NO-STAKE-FOUND))
    (stake-amount (get amount stake-data))
    (locked-until (get locked-until stake-data))
    (created-at (get created-at stake-data))
    (reward-rate (get reward-rate stake-data))
    (staking-duration (- block-height created-at))
    (reward-amount (/ (* stake-amount reward-rate staking-duration) (* u10000 u144)))
  )
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED-PROTOCOL)
    (asserts! (>= block-height locked-until) ERR-STAKING-PERIOD-NOT-ENDED)

    (try! (as-contract (stx-transfer? stake-amount tx-sender tx-sender)))
    (try! (as-contract (stx-transfer? reward-amount tx-sender tx-sender)))

    (map-delete staking-positions { staker: tx-sender, stake-id: stake-id })

    (ok { amount: stake-amount, reward: reward-amount })
  )
)

;; Read-only functions
(define-read-only (get-pool-info (pool-id uint))
  (map-get? pools { pool-id: pool-id })
)

(define-read-only (get-liquidity-position (provider principal) (pool-id uint))
  (map-get? liquidity-positions { provider: provider, pool-id: pool-id })
)

(define-read-only (get-staking-position (staker principal) (stake-id uint))
  (map-get? staking-positions { staker: staker, stake-id: stake-id })
)

(define-read-only (get-pool-count)
  (var-get pool-count)
)

(define-read-only (get-protocol-fee-rate)
  (var-get protocol-fee-rate)
)

(define-read-only (is-protocol-paused)
  (var-get protocol-paused)
)

(define-read-only (get-total-fees-collected)
  (var-get total-fees-collected)
)

(define-read-only (get-swap-output (pool-id uint) (token-in principal) (amount-in uint))
  (match (map-get? pools { pool-id: pool-id })
    pool-data
    (let (
      (is-token-a (is-eq token-in (get token-a pool-data)))
      (reserve-in (if is-token-a (get reserve-a pool-data) (get reserve-b pool-data)))
      (reserve-out (if is-token-a (get reserve-b pool-data) (get reserve-a pool-data)))
    )
      (ok (calculate-constant-product-output amount-in reserve-in reserve-out (get fee-rate pool-data)))
    )
    ERR-POOL-NOT-EXISTS
  )
)

(define-read-only (get-trading-pair (token-a principal) (token-b principal))
  (map-get? trading-pairs { token-a: token-a, token-b: token-b })
)