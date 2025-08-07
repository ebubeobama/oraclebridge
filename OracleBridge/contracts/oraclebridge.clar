;; Oracle Bridge - Decentralized Price Oracle Aggregator

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-invalid-feed (err u101))
(define-constant err-feed-exists (err u102))
(define-constant err-feed-not-found (err u103))
(define-constant err-stale-data (err u104))
(define-constant err-invalid-price (err u105))
(define-constant err-insufficient-sources (err u106))
(define-constant err-reporter-exists (err u107))
(define-constant err-reporter-not-found (err u108))
(define-constant err-deviation-exceeded (err u109))
(define-constant err-update-too-soon (err u110))
(define-constant err-invalid-weight (err u111))
(define-constant err-paused (err u112))
(define-constant err-invalid-threshold (err u113))

;; Data Variables
(define-data-var feed-counter uint u0)
(define-data-var reporter-counter uint u0)
(define-data-var min-reporters uint u3)
(define-data-var max-deviation uint u500) ;; 5% = 500 basis points
(define-data-var staleness-threshold uint u360) ;; ~1 hour in blocks
(define-data-var update-interval uint u6) ;; ~1 minute minimum between updates
(define-data-var total-updates uint u0)
(define-data-var emergency-pause bool false)

;; Data Maps
(define-map price-feeds
    uint
    {
        symbol: (string-ascii 10),
        decimals: uint,
        current-price: uint,
        twap-price: uint,
        last-update: uint,
        update-count: uint,
        min-sources: uint,
        active: bool
    }
)

(define-map feed-updates
    {feed-id: uint, block: uint}
    {
        price: uint,
        sources: uint,
        timestamp: uint,
        valid: bool
    }
)

(define-map reporters
    uint
    {
        address: principal,
        name: (string-utf8 50),
        reputation: uint,
        total-reports: uint,
        valid-reports: uint,
        weight: uint,
        active: bool
    }
)

(define-map reporter-submissions
    {feed-id: uint, reporter-id: uint, round: uint}
    {
        price: uint,
        timestamp: uint,
        used: bool
    }
)

(define-map feed-aggregation
    {feed-id: uint, round: uint}
    {
        submissions: (list 20 {reporter: uint, price: uint, weight: uint}),
        median-price: uint,
        weighted-avg: uint,
        finalized: bool
    }
)

(define-map twap-window
    {feed-id: uint, window-id: uint}
    {
        sum-price: uint,
        sum-weight: uint,
        samples: uint
    }
)

(define-map feed-reporters
    uint
    (list 20 uint)
)

;; Private Functions
(define-private (calculate-median (prices (list 20 uint)))
    (let ((sorted-prices (unwrap! (sort-prices prices) u0))
          (len (len sorted-prices)))
        (if (is-eq len u0)
            u0
            (if (is-eq (mod len u2) u0)
                (/ (+ (unwrap! (element-at sorted-prices (/ len u2)) u0)
                     (unwrap! (element-at sorted-prices (- (/ len u2) u1)) u0)) u2)
                (unwrap! (element-at sorted-prices (/ len u2)) u0)
            )
        )
    )
)

(define-private (sort-prices (prices (list 20 uint)))
    (ok prices)
)

(define-private (calculate-weighted-average (submissions (list 20 {reporter: uint, price: uint, weight: uint})))
    (let ((result (fold accumulate-weighted submissions {sum: u0, weight: u0})))
        (if (> (get weight result) u0)
            (/ (get sum result) (get weight result))
            u0
        )
    )
)

(define-private (accumulate-weighted (submission {reporter: uint, price: uint, weight: uint}) 
                                     (acc {sum: uint, weight: uint}))
    {
        sum: (+ (get sum acc) (* (get price submission) (get weight submission))),
        weight: (+ (get weight acc) (get weight submission))
    }
)

(define-private (check-deviation (new-price uint) (current-price uint))
    (if (is-eq current-price u0)
        true
        (let ((deviation (if (> new-price current-price)
                            (/ (* (- new-price current-price) u10000) current-price)
                            (/ (* (- current-price new-price) u10000) current-price))))
            (<= deviation (var-get max-deviation))
        )
    )
)

(define-private (update-twap (feed-id uint) (new-price uint))
    (let ((window-id (/ stacks-block-height u360)))
        (match (map-get? twap-window {feed-id: feed-id, window-id: window-id})
            existing
            (map-set twap-window {feed-id: feed-id, window-id: window-id}
                {
                    sum-price: (+ (get sum-price existing) new-price),
                    sum-weight: (+ (get sum-weight existing) u1),
                    samples: (+ (get samples existing) u1)
                })
            (map-set twap-window {feed-id: feed-id, window-id: window-id}
                {
                    sum-price: new-price,
                    sum-weight: u1,
                    samples: u1
                })
        )
        true
    )
)

(define-private (calculate-twap (feed-id uint))
    (let ((current-window (/ stacks-block-height u360))
          (window-1 (map-get? twap-window {feed-id: feed-id, window-id: current-window}))
          (window-2 (map-get? twap-window {feed-id: feed-id, window-id: (- current-window u1)}))
          (window-3 (map-get? twap-window {feed-id: feed-id, window-id: (- current-window u2)})))
        (let ((sum-1 (match window-1 w (get sum-price w) u0))
              (sum-2 (match window-2 w (get sum-price w) u0))
              (sum-3 (match window-3 w (get sum-price w) u0))
              (samples-1 (match window-1 w (get samples w) u0))
              (samples-2 (match window-2 w (get samples w) u0))
              (samples-3 (match window-3 w (get samples w) u0)))
            (let ((total-sum (+ sum-1 sum-2 sum-3))
                  (total-samples (+ samples-1 samples-2 samples-3)))
                (if (> total-samples u0)
                    (/ total-sum total-samples)
                    u0)
            )
        )
    )
)

(define-private (update-reporter-reputation (reporter-id uint) (valid bool))
    (match (map-get? reporters reporter-id)
        reporter
        (map-set reporters reporter-id
            (merge reporter {
                total-reports: (+ (get total-reports reporter) u1),
                valid-reports: (if valid (+ (get valid-reports reporter) u1) (get valid-reports reporter)),
                reputation: (if valid 
                               (min u1000 (+ (get reputation reporter) u10))
                               (if (> (get reputation reporter) u10) (- (get reputation reporter) u10) u0))
            }))
        false
    )
)

(define-private (min (a uint) (b uint))
    (if (<= a b) a b)
)

(define-private (is-reporter-authorized (feed-id uint) (reporter-id uint))
    (match (map-get? feed-reporters feed-id)
        authorized-list
        (is-some (index-of authorized-list reporter-id))
        false
    )
)

;; Public Functions
(define-public (create-feed (symbol (string-ascii 10)) (decimals uint) (min-sources uint))
    (let ((feed-id (+ (var-get feed-counter) u1)))
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= decimals u18) err-invalid-feed)
        (asserts! (>= min-sources (var-get min-reporters)) err-insufficient-sources)
        
        (map-set price-feeds feed-id {
            symbol: symbol,
            decimals: decimals,
            current-price: u0,
            twap-price: u0,
            last-update: u0,
            update-count: u0,
            min-sources: min-sources,
            active: true
        })
        
        (var-set feed-counter feed-id)
        (ok feed-id)
    )
)

(define-public (register-reporter (name (string-utf8 50)) (initial-weight uint))
    (let ((reporter-id (+ (var-get reporter-counter) u1)))
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= initial-weight u100) err-invalid-weight)
        
        (map-set reporters reporter-id {
            address: tx-sender,
            name: name,
            reputation: u500,
            total-reports: u0,
            valid-reports: u0,
            weight: initial-weight,
            active: true
        })
        
        (var-set reporter-counter reporter-id)
        (ok reporter-id)
    )
)

(define-public (authorize-reporter (feed-id uint) (reporter-id uint))
    (let ((feed (unwrap! (map-get? price-feeds feed-id) err-feed-not-found))
          (reporter (unwrap! (map-get? reporters reporter-id) err-reporter-not-found))
          (current-reporters (default-to (list) (map-get? feed-reporters feed-id))))
        
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (get active reporter) err-invalid-feed)
        (asserts! (is-none (index-of current-reporters reporter-id)) err-reporter-exists)
        
        (match (as-max-len? (append current-reporters reporter-id) u20)
            new-list
            (begin
                (map-set feed-reporters feed-id new-list)
                (ok true))
            err-invalid-feed
        )
    )
)

(define-public (submit-price (feed-id uint) (reporter-id uint) (price uint) (round uint))
    (let ((feed (unwrap! (map-get? price-feeds feed-id) err-feed-not-found))
          (reporter (unwrap! (map-get? reporters reporter-id) err-reporter-not-found)))
        
        (asserts! (not (var-get emergency-pause)) err-paused)
        (asserts! (is-eq tx-sender (get address reporter)) err-unauthorized)
        (asserts! (get active feed) err-invalid-feed)
        (asserts! (get active reporter) err-invalid-feed)
        (asserts! (is-reporter-authorized feed-id reporter-id) err-unauthorized)
        (asserts! (> price u0) err-invalid-price)
        (asserts! (>= (- stacks-block-height (get last-update feed)) (var-get update-interval)) err-update-too-soon)
        
        (map-set reporter-submissions {feed-id: feed-id, reporter-id: reporter-id, round: round} {
            price: price,
            timestamp: stacks-block-height,
            used: false
        })
        
        (match (map-get? feed-aggregation {feed-id: feed-id, round: round})
            existing
            (match (as-max-len? (append (get submissions existing) 
                                       {reporter: reporter-id, price: price, weight: (get weight reporter)}) u20)
                new-submissions
                (map-set feed-aggregation {feed-id: feed-id, round: round}
                    (merge existing {submissions: new-submissions}))
                false)
            (map-set feed-aggregation {feed-id: feed-id, round: round} {
                submissions: (list {reporter: reporter-id, price: price, weight: (get weight reporter)}),
                median-price: u0,
                weighted-avg: u0,
                finalized: false
            })
        )
        
        (ok true)
    )
)

(define-public (finalize-round (feed-id uint) (round uint))
    (let ((feed (unwrap! (map-get? price-feeds feed-id) err-feed-not-found))
          (aggregation (unwrap! (map-get? feed-aggregation {feed-id: feed-id, round: round}) err-invalid-feed)))
        
        (asserts! (not (get finalized aggregation)) err-invalid-feed)
        (asserts! (>= (len (get submissions aggregation)) (get min-sources feed)) err-insufficient-sources)
        
        (let ((prices (map extract-price (get submissions aggregation)))
              (median (calculate-median prices))
              (weighted-avg (calculate-weighted-average (get submissions aggregation))))
            
            (asserts! (check-deviation weighted-avg (get current-price feed)) err-deviation-exceeded)
            
            (map-set price-feeds feed-id
                (merge feed {
                    current-price: weighted-avg,
                    twap-price: (calculate-twap feed-id),
                    last-update: stacks-block-height,
                    update-count: (+ (get update-count feed) u1)
                }))
            
            (map-set feed-aggregation {feed-id: feed-id, round: round}
                (merge aggregation {
                    median-price: median,
                    weighted-avg: weighted-avg,
                    finalized: true
                }))
            
            (map-set feed-updates {feed-id: feed-id, block: stacks-block-height} {
                price: weighted-avg,
                sources: (len (get submissions aggregation)),
                timestamp: stacks-block-height,
                valid: true
            })
            
            (update-twap feed-id weighted-avg)
            (var-set total-updates (+ (var-get total-updates) u1))
            
            (ok weighted-avg)
        )
    )
)

(define-private (extract-price (submission {reporter: uint, price: uint, weight: uint}))
    (get price submission)
)

(define-public (update-reporter-weight (reporter-id uint) (new-weight uint))
    (let ((reporter (unwrap! (map-get? reporters reporter-id) err-reporter-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= new-weight u100) err-invalid-weight)
        
        (map-set reporters reporter-id
            (merge reporter {weight: new-weight}))
        
        (ok true)
    )
)

(define-public (pause-feed (feed-id uint) (paused bool))
    (let ((feed (unwrap! (map-get? price-feeds feed-id) err-feed-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        
        (map-set price-feeds feed-id
            (merge feed {active: (not paused)}))
        
        (ok true)
    )
)

(define-public (toggle-emergency)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set emergency-pause (not (var-get emergency-pause)))
        (ok (var-get emergency-pause))
    )
)

(define-public (update-parameters (param (string-ascii 20)) (value uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        
        (if (is-eq param "min-reporters")
            (begin
                (asserts! (>= value u1) err-invalid-threshold)
                (var-set min-reporters value))
        (if (is-eq param "max-deviation")
            (begin
                (asserts! (<= value u2000) err-invalid-threshold)
                (var-set max-deviation value))
        (if (is-eq param "staleness")
            (var-set staleness-threshold value)
        (if (is-eq param "interval")
            (var-set update-interval value)
            false))))
        
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-price (feed-id uint))
    (match (map-get? price-feeds feed-id)
        feed 
        (if (< (- stacks-block-height (get last-update feed)) (var-get staleness-threshold))
            (ok (get current-price feed))
            err-stale-data)
        err-feed-not-found
    )
)

(define-read-only (get-twap (feed-id uint))
    (match (map-get? price-feeds feed-id)
        feed (ok (get twap-price feed))
        err-feed-not-found
    )
)

(define-read-only (get-feed (feed-id uint))
    (map-get? price-feeds feed-id)
)

(define-read-only (get-reporter (reporter-id uint))
    (map-get? reporters reporter-id)
)

(define-read-only (get-feed-reporters (feed-id uint))
    (default-to (list) (map-get? feed-reporters feed-id))
)

(define-read-only (get-aggregation (feed-id uint) (round uint))
    (map-get? feed-aggregation {feed-id: feed-id, round: round})
)

(define-read-only (is-price-fresh (feed-id uint))
    (match (map-get? price-feeds feed-id)
        feed (< (- stacks-block-height (get last-update feed)) (var-get staleness-threshold))
        false
    )
)

(define-read-only (get-protocol-stats)
    {
        total-feeds: (var-get feed-counter),
        total-reporters: (var-get reporter-counter),
        total-updates: (var-get total-updates),
        min-reporters: (var-get min-reporters),
        max-deviation: (var-get max-deviation),
        staleness-threshold: (var-get staleness-threshold),
        emergency-pause: (var-get emergency-pause)
    }
)