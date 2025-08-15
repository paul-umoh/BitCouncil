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