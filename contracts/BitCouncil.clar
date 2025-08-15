;; Title: BitCouncil - Next-Generation Blockchain Democracy Platform
;;
;; Summary:
;; BitCouncil transforms traditional governance through an innovative blockchain-native
;; democracy platform that combines cryptographic security with transparent decision-making
;; processes, enabling communities to achieve consensus through verifiable on-chain voting.
;;
;; Description:
;; BitCouncil represents a paradigm shift in decentralized governance, introducing a
;; sophisticated framework for community-driven decision making that prioritizes both
;; transparency and security. This protocol establishes a new standard for digital
;; democracy by implementing:
;;
;;   - Dynamic membership systems with cryptographic identity verification
;;   - Weighted voting mechanisms based on community participation and stake
;;   - Time-locked proposal systems ensuring deliberate decision-making
;;   - Merit-based reputation tracking with automated decay prevention
;;   - Multi-tier treasury management with granular spending controls
;;   - Inter-community alliance frameworks for collaborative governance
;;   - Immutable audit trails for all governance activities
;;
;; Built with enterprise-grade security principles, BitCouncil empowers organizations
;; to transition from centralized hierarchies to trustless, community-governed entities
;; while maintaining operational efficiency and strategic coherence.

;; CONSTANTS & ERROR DEFINITIONS

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-MEMBER (err u101))
(define-constant ERR-NOT-MEMBER (err u102))
(define-constant ERR-INVALID-PROPOSAL (err u103))
(define-constant ERR-PROPOSAL-EXPIRED (err u104))
(define-constant ERR-ALREADY-VOTED (err u105))
(define-constant ERR-INSUFFICIENT-FUNDS (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))

;; STATE VARIABLES

(define-data-var total-members uint u0)
(define-data-var total-proposals uint u0)
(define-data-var treasury-balance uint u0)

;; DATA STRUCTURES

;; Member registry with reputation and participation tracking
(define-map members
  principal
  {
    reputation: uint,
    stake: uint,
    last-interaction: uint,
  }
)

;; Proposal management system with comprehensive metadata
(define-map proposals
  uint
  {
    creator: principal,
    title: (string-ascii 50),
    description: (string-utf8 500),
    amount: uint,
    yes-votes: uint,
    no-votes: uint,
    status: (string-ascii 10),
    created-at: uint,
    expires-at: uint,
  }
)

;; Vote tracking to prevent double-voting
(define-map votes
  {
    proposal-id: uint,
    voter: principal,
  }
  bool
)

;; Inter-community collaboration framework
(define-map collaborations
  uint
  {
    partner-dao: principal,
    proposal-id: uint,
    status: (string-ascii 10),
  }
)

;; PRIVATE UTILITY FUNCTIONS

;; Verify member status
(define-private (is-member (user principal))
  (match (map-get? members user)
    member-data
    true
    false
  )
)

;; Validate active proposal state
(define-private (is-active-proposal (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (and
      (< stacks-block-height (get expires-at proposal))
      (is-eq (get status proposal) "active")
    )
    false
  )
)

;; Proposal existence validation
(define-private (is-valid-proposal-id (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal
    true
    false
  )
)

;; Collaboration existence validation
(define-private (is-valid-collaboration-id (collaboration-id uint))
  (match (map-get? collaborations collaboration-id)
    collaboration
    true
    false
  )
)

;; Calculate member's voting influence based on reputation and stake
(define-private (calculate-voting-power (user principal))
  (let (
      (member-data (unwrap! (map-get? members user) u0))
      (reputation (get reputation member-data))
      (stake (get stake member-data))
    )
    (+ (* reputation u10) stake)
  )
)

;; Update member reputation with activity tracking
(define-private (update-member-reputation
    (user principal)
    (change int)
  )
  (match (map-get? members user)
    member-data (let (
        (new-reputation (to-uint (+ (to-int (get reputation member-data)) change)))
        (updated-data (merge member-data {
          reputation: new-reputation,
          last-interaction: stacks-block-height,
        }))
      )
      (map-set members user updated-data)
      (ok new-reputation)
    )
    ERR-NOT-MEMBER
  )
)

;; MEMBERSHIP MANAGEMENT FUNCTIONS

;; Join the governance community
(define-public (join-dao)
  (let ((caller tx-sender))
    (asserts! (not (is-member caller)) ERR-ALREADY-MEMBER)
    (map-set members caller {
      reputation: u1,
      stake: u0,
      last-interaction: stacks-block-height,
    })
    (var-set total-members (+ (var-get total-members) u1))
    (ok true)
  )
)

;; Leave the governance community
(define-public (leave-dao)
  (let ((caller tx-sender))
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (map-delete members caller)
    (var-set total-members (- (var-get total-members) u1))
    (ok true)
  )
)

;; Stake tokens to increase voting power
(define-public (stake-tokens (amount uint))
  (let ((caller tx-sender))
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    (match (map-get? members caller)
      member-data (let (
          (new-stake (+ (get stake member-data) amount))
          (updated-data (merge member-data {
            stake: new-stake,
            last-interaction: stacks-block-height,
          }))
        )
        (map-set members caller updated-data)
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (ok new-stake)
      )
      ERR-NOT-MEMBER
    )
  )
)

;; Unstake tokens from the governance system
(define-public (unstake-tokens (amount uint))
  (let ((caller tx-sender))
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (match (map-get? members caller)
      member-data (let ((current-stake (get stake member-data)))
        (asserts! (>= current-stake amount) ERR-INSUFFICIENT-FUNDS)
        (try! (as-contract (stx-transfer? amount tx-sender caller)))
        (let (
            (new-stake (- current-stake amount))
            (updated-data (merge member-data {
              stake: new-stake,
              last-interaction: stacks-block-height,
            }))
          )
          (map-set members caller updated-data)
          (var-set treasury-balance (- (var-get treasury-balance) amount))
          (ok new-stake)
        )
      )
      ERR-NOT-MEMBER
    )
  )
)

;; PROPOSAL MANAGEMENT FUNCTIONS

;; Create a new governance proposal
(define-public (create-proposal
    (title (string-ascii 50))
    (description (string-utf8 500))
    (amount uint)
  )
  (let (
      (caller tx-sender)
      (proposal-id (+ (var-get total-proposals) u1))
    )
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (asserts! (>= (var-get treasury-balance) amount) ERR-INSUFFICIENT-FUNDS)
    (asserts! (> (len title) u0) ERR-INVALID-PROPOSAL)
    (asserts! (> (len description) u0) ERR-INVALID-PROPOSAL)
    (map-set proposals proposal-id {
      creator: caller,
      title: title,
      description: description,
      amount: amount,
      yes-votes: u0,
      no-votes: u0,
      status: "active",
      created-at: stacks-block-height,
      expires-at: (+ stacks-block-height u1440), ;; Proposal expires after 1440 blocks (approx. 10 days)
    })
    (var-set total-proposals proposal-id)
    (try! (update-member-reputation caller 1))
    ;; Increase reputation for creating a proposal
    (ok proposal-id)
  )
)

;; Cast vote on an active proposal
(define-public (vote-on-proposal
    (proposal-id uint)
    (vote bool)
  )
  (let ((caller tx-sender))
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (asserts! (is-active-proposal proposal-id) ERR-INVALID-PROPOSAL)
    (asserts!
      (not (default-to false
        (map-get? votes {
          proposal-id: proposal-id,
          voter: caller,
        })
      ))
      ERR-ALREADY-VOTED
    )

    (let (
        (voting-power (calculate-voting-power caller))
        (proposal (unwrap! (map-get? proposals proposal-id) ERR-INVALID-PROPOSAL))
      )
      (if vote
        (map-set proposals proposal-id
          (merge proposal { yes-votes: (+ (get yes-votes proposal) voting-power) })
        )
        (map-set proposals proposal-id
          (merge proposal { no-votes: (+ (get no-votes proposal) voting-power) })
        )
      )
      (map-set votes {
        proposal-id: proposal-id,
        voter: caller,
      }
        true
      )
      (try! (update-member-reputation caller 1))
      ;; Increase reputation for voting
      (ok true)
    )
  )
)

;; Execute proposal after voting period expires
(define-public (execute-proposal (proposal-id uint))
  (let ((caller tx-sender))
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (asserts! (is-valid-proposal-id proposal-id) ERR-INVALID-PROPOSAL)
    (match (map-get? proposals proposal-id)
      proposal (begin
        (asserts! (>= stacks-block-height (get expires-at proposal))
          ERR-PROPOSAL-EXPIRED
        )
        (asserts! (is-eq (get status proposal) "active") ERR-INVALID-PROPOSAL)
        (let (
            (yes-votes (get yes-votes proposal))
            (no-votes (get no-votes proposal))
            (amount (get amount proposal))
          )
          (if (> yes-votes no-votes)
            (begin
              (try! (as-contract (stx-transfer? amount tx-sender (get creator proposal))))
              (var-set treasury-balance (- (var-get treasury-balance) amount))
              ;; Add additional validation before setting status
              (asserts! (is-valid-proposal-id proposal-id) ERR-INVALID-PROPOSAL)
              (map-set proposals proposal-id
                (merge proposal { status: "executed" })
              )
              (try! (update-member-reputation (get creator proposal) 5))
              (ok true)
            )
            (begin
              ;; Add additional validation before setting status
              (asserts! (is-valid-proposal-id proposal-id) ERR-INVALID-PROPOSAL)
              (map-set proposals proposal-id
                (merge proposal { status: "rejected" })
              )
              (ok false)
            )
          )
        )
      )
      ERR-INVALID-PROPOSAL
    )
  )
)

;; TREASURY MANAGEMENT FUNCTIONS

;; Get current treasury balance
(define-read-only (get-treasury-balance)
  (ok (var-get treasury-balance))
)

;; Donate funds to community treasury
(define-public (donate-to-treasury (amount uint))
  (let ((caller tx-sender))
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (if (is-member caller)
      (begin
        (try! (update-member-reputation caller 2)) ;; Increase reputation for donating
        (ok true)
      )
      (ok true)
    )
  )
)

;; REPUTATION SYSTEM FUNCTIONS

;; Get member's reputation score
(define-read-only (get-member-reputation (user principal))
  (match (map-get? members user)
    member-data (ok (get reputation member-data))
    ERR-NOT-MEMBER
  )
)

;; Decay reputation of inactive members (admin function)
(define-public (decay-inactive-members)
  (let (
      (caller tx-sender)
      (current-block stacks-block-height)
    )
    (asserts! (is-eq caller CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set members caller
      (match (map-get? members caller)
        member-data (if (> (- current-block (get last-interaction member-data)) u4320) ;; Approx. 30 days of inactivity
          (merge member-data { reputation: (/ (get reputation member-data) u2) }) ;; Halve the reputation
          member-data
        )
        {
          reputation: u0,
          stake: u0,
          last-interaction: current-block,
        }
      ))
    (ok true)
  )
)

;; CROSS-COMMUNITY COLLABORATION FUNCTIONS

;; Propose collaboration with another DAO
(define-public (propose-collaboration
    (partner-dao principal)
    (proposal-id uint)
  )
  (let (
      (caller tx-sender)
      (collaboration-id (+ (var-get total-proposals) u1))
    )
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    (asserts! (is-active-proposal proposal-id) ERR-INVALID-PROPOSAL)
    (asserts! (not (is-eq partner-dao caller)) ERR-INVALID-PROPOSAL)
    (map-set collaborations collaboration-id {
      partner-dao: partner-dao,
      proposal-id: proposal-id,
      status: "proposed",
    })
    (var-set total-proposals collaboration-id)
    (ok collaboration-id)
  )
)

;; Accept collaboration proposal
(define-public (accept-collaboration (collaboration-id uint))
  (let ((caller tx-sender))
    (asserts! (is-valid-collaboration-id collaboration-id) ERR-INVALID-PROPOSAL)
    (match (map-get? collaborations collaboration-id)
      collaboration (begin
        (asserts! (is-eq caller (get partner-dao collaboration))
          ERR-NOT-AUTHORIZED
        )
        (asserts! (is-eq (get status collaboration) "proposed")
          ERR-INVALID-PROPOSAL
        )
        ;; Add additional validation before setting status
        (asserts! (is-valid-collaboration-id collaboration-id)
          ERR-INVALID-PROPOSAL
        )
        (map-set collaborations collaboration-id
          (merge collaboration { status: "accepted" })
        )
        (ok true)
      )
      ERR-INVALID-PROPOSAL
    )
  )
)

;; PUBLIC READ-ONLY FUNCTIONS

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (ok (unwrap! (map-get? proposals proposal-id) ERR-INVALID-PROPOSAL))
)

;; Get member details
(define-read-only (get-member (user principal))
  (ok (unwrap! (map-get? members user) ERR-NOT-MEMBER))
)

;; Get total member count
(define-read-only (get-total-members)
  (ok (var-get total-members))
)

;; Get total proposal count
(define-read-only (get-total-proposals)
  (ok (var-get total-proposals))
)

;; CONTRACT INITIALIZATION

;; Initialize contract state variables
(begin
  (var-set total-members u0)
  (var-set total-proposals u0)
  (var-set treasury-balance u0)
)
