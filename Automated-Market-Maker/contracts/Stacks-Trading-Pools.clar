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
(define-constant ERR-ARITHMETIC-OVERFLOW (err u1016))
(define-constant ERR-INVALID-CURVE-TYPE (err u1017))

;; Protocol constants
(define-constant contract-owner tx-sender)
(define-constant max-fee-rate u10000)
(define-constant min-liquidity u1000)
(define-constant max-pools u1000)
(define-constant staking-reward-rate u500)
(define-constant curve-precision u1000000)
(define-constant max-uint u340282366920938463463374607431768211455)
(define-constant max-amount u1000000000000000000) ;; 1 billion STX with 6 decimals
(define-constant max-lock-period u525600) ;; ~1 year in blocks
(define-constant min-lock-period u144) ;; ~1 day in blocks

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

(define-private (safe-multiply (a uint) (b uint))
  (if (or (is-eq a u0) (is-eq b u0))
    (ok u0)
    (if (<= a (/ max-uint b))
      (ok (* a b))
      ERR-ARITHMETIC-OVERFLOW
    )
  )
)

(define-private (safe-add (a uint) (b uint))
  (if (<= a (- max-uint b))
    (ok (+ a b))
    ERR-ARITHMETIC-OVERFLOW
  )
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
  (if (and (> input-amount u0) (<= input-amount max-amount) (> input-reserve u0) (> output-reserve u0))
    (let (
      (fee-amount (/ (* input-amount fee-rate) u10000))
      (input-amount-with-fee (- input-amount fee-amount))
      (numerator (* input-amount-with-fee output-reserve))
      (denominator (+ input-reserve input-amount-with-fee))
    )
      (if (> denominator u0)
        (/ numerator denominator)
        u0
      )
    )
    u0
  )
)

(define-private (validate-curve-type (curve-type (string-ascii 10)))
  (or 
    (is-eq curve-type "linear")
    (is-eq curve-type "exponential")
    (is-eq curve-type "constant")
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

(define-private (validate-pool-id (pool-id uint))
  (and (> pool-id u0) (<= pool-id (var-get pool-count)))
)

(define-private (validate-amounts (amount-a uint) (amount-b uint))
  (and 
    (> amount-a u0) 
    (> amount-b u0)
    (<= amount-a max-amount)
    (<= amount-b max-amount)
  )
)

(define-private (validate-amount (amount uint))
  (and (> amount u0) (<= amount max-amount))
)

(define-private (validate-staking-token (token principal))
  (not (is-eq token (as-contract tx-sender)))
)

(define-private (update-pool-reserves (pool-id uint) (new-reserve-a uint) (new-reserve-b uint))
  (if (validate-pool-id pool-id)
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
    ERR-INVALID-POOL-ID
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
    (validated-amounts (validate-amounts initial-a initial-b))
    (lp-tokens-calc (unwrap! (safe-multiply initial-a initial-b) ERR-ARITHMETIC-OVERFLOW))
    (lp-tokens (sqrt lp-tokens-calc))
  )
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED-PROTOCOL)
    (asserts! (not (is-eq token-a token-b)) ERR-INVALID-TOKEN-PAIR)
    (asserts! validated-amounts ERR-INVALID-AMOUNT)
    (asserts! (<= fee-rate max-fee-rate) ERR-INVALID-FEE-RATE)
    (asserts! (< (var-get pool-count) max-pools) ERR-INVALID-POOL-ID)
    (asserts! (is-none (map-get? trading-pairs { token-a: token-a, token-b: token-b })) ERR-POOL-ALREADY-EXISTS)
    (asserts! (is-none (map-get? trading-pairs { token-a: token-b, token-b: token-a })) ERR-POOL-ALREADY-EXISTS)
    (asserts! (>= lp-tokens min-liquidity) ERR-ZERO-LIQUIDITY)
    (asserts! (validate-curve-type curve-type) ERR-INVALID-CURVE-TYPE)
    (asserts! (and (> curve-param-a u0) (<= curve-param-a curve-precision)) ERR-INVALID-CURVE-PARAMETERS)
    (asserts! (<= curve-param-b curve-precision) ERR-INVALID-CURVE-PARAMETERS)

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
  (begin
    ;; Validate inputs first
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED-PROTOCOL)
    (asserts! (validate-pool-id pool-id) ERR-INVALID-POOL-ID)
    (asserts! (validate-amounts amount-a amount-b) ERR-INVALID-AMOUNT)
    
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
      (new-reserve-a (unwrap! (safe-add reserve-a amount-a) ERR-ARITHMETIC-OVERFLOW))
      (new-reserve-b (unwrap! (safe-add reserve-b amount-b) ERR-ARITHMETIC-OVERFLOW))
    )
      (asserts! (get is-active pool-data) ERR-POOL-NOT-EXISTS)
      (asserts! (>= lp-tokens min-lp-tokens) ERR-SLIPPAGE-EXCEEDED)

      (try! (stx-transfer? amount-a tx-sender (as-contract tx-sender)))
      (try! (stx-transfer? amount-b tx-sender (as-contract tx-sender)))

      (try! (update-pool-reserves pool-id new-reserve-a new-reserve-b))

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
    (asserts! (validate-pool-id pool-id) ERR-INVALID-POOL-ID)
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
    (validated-amount-in (and (> amount-in u0) (<= amount-in max-amount)))
    (amount-out (if validated-amount-in 
                   (calculate-constant-product-output amount-in reserve-in reserve-out (get fee-rate pool-data))
                   u0))
    (fee-amount (/ (* amount-in (get fee-rate pool-data)) u10000))
    (new-reserve-in (+ reserve-in amount-in))
    (new-reserve-out (- reserve-out amount-out))
  )
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED-PROTOCOL)
    (asserts! (validate-pool-id pool-id) ERR-INVALID-POOL-ID)
    (asserts! (get is-active pool-data) ERR-POOL-NOT-EXISTS)
    (asserts! (<= block-height deadline) ERR-DEADLINE-EXCEEDED)
    (asserts! validated-amount-in ERR-INVALID-AMOUNT)
    (asserts! (>= amount-out min-amount-out) ERR-SLIPPAGE-EXCEEDED)
    (asserts! (or (is-eq token-in (get token-a pool-data)) (is-eq token-in (get token-b pool-data))) ERR-INVALID-TOKEN-PAIR)

    (try! (stx-transfer? amount-in tx-sender (as-contract tx-sender)))
    (try! (as-contract (stx-transfer? amount-out tx-sender tx-sender)))

    (if is-token-a
      (try! (update-pool-reserves pool-id new-reserve-in new-reserve-out))
      (try! (update-pool-reserves pool-id new-reserve-out new-reserve-in))
    )

    (var-set total-fees-collected (+ (var-get total-fees-collected) fee-amount))

    (ok amount-out)
  )
)

;; Staking functions
(define-public (stake-tokens (token principal) (amount uint) (lock-period uint))
  (begin
    ;; Validate inputs immediately
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED-PROTOCOL)
    (asserts! (and (> amount u0) (<= amount max-amount)) ERR-INVALID-AMOUNT)
    (asserts! (and (>= lock-period min-lock-period) (<= lock-period max-lock-period)) ERR-INVALID-AMOUNT)
    (asserts! (validate-staking-token token) ERR-INVALID-TOKEN-PAIR)
    
    (let (
      (stake-id (get-next-stake-id tx-sender))
      (current-count (default-to u0 (get count (map-get? user-stake-count { user: tx-sender }))))
      (lock-until (unwrap! (safe-add block-height lock-period) ERR-ARITHMETIC-OVERFLOW))
    )
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
    (asserts! (> stake-id u0) ERR-INVALID-AMOUNT)
    (asserts! (>= block-height locked-until) ERR-STAKING-PERIOD-NOT-ENDED)

    (try! (as-contract (stx-transfer? stake-amount tx-sender tx-sender)))
    (try! (as-contract (stx-transfer? reward-amount tx-sender tx-sender)))

    (map-delete staking-positions { staker: tx-sender, stake-id: stake-id })

    (ok { amount: stake-amount, reward: reward-amount })
  )
)

;; Read-only functions
(define-read-only (get-pool-info (pool-id uint))
  (if (validate-pool-id pool-id)
    (map-get? pools { pool-id: pool-id })
    none
  )
)

(define-read-only (get-liquidity-position (provider principal) (pool-id uint))
  (if (validate-pool-id pool-id)
    (map-get? liquidity-positions { provider: provider, pool-id: pool-id })
    none
  )
)

(define-read-only (get-staking-position (staker principal) (stake-id uint))
  (if (> stake-id u0)
    (map-get? staking-positions { staker: staker, stake-id: stake-id })
    none
  )
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
  (if (and (validate-pool-id pool-id) (validate-amount amount-in))
    (match (map-get? pools { pool-id: pool-id })
      pool-data
      (let (
        (is-token-a (is-eq token-in (get token-a pool-data)))
        (reserve-in (if is-token-a (get reserve-a pool-data) (get reserve-b pool-data)))
        (reserve-out (if is-token-a (get reserve-b pool-data) (get reserve-a pool-data)))
      )
        (if (or (is-eq token-in (get token-a pool-data)) (is-eq token-in (get token-b pool-data)))
          (ok (calculate-constant-product-output amount-in reserve-in reserve-out (get fee-rate pool-data)))
          ERR-INVALID-TOKEN-PAIR
        )
      )
      ERR-POOL-NOT-EXISTS
    )
    (if (validate-pool-id pool-id)
      ERR-INVALID-AMOUNT
      ERR-INVALID-POOL-ID
    )
  )
)

(define-read-only (get-trading-pair (token-a principal) (token-b principal))
  (map-get? trading-pairs { token-a: token-a, token-b: token-b })
)