import Testing
import Foundation
@testable import grid

struct GridIdentityLogicTests {
    @Test func interestNamesCollapseToOneCatalogKey() {
        #expect(GridIdentityLogic.normalizeInterestName("  Dodge   Ball ") == "dodge ball")
        #expect(GridIdentityLogic.normalizeInterestName("COFFEE") == "coffee")
        #expect(GridIdentityLogic.normalizeInterestName("   ") == nil)
    }

    @Test func remoteAccountWinsOverThisPhone() {
        let resolved = GridIdentityLogic.accountID(stored: "local", lookup: .found("remote"))
        #expect(resolved?.id == "remote")
        #expect(resolved?.isNew == false)
    }

    @Test func failedLookupDoesNotMintASecondAccount() {
        #expect(GridIdentityLogic.accountID(stored: "local", lookup: .failed)?.id == "local")
        #expect(GridIdentityLogic.accountID(stored: nil, lookup: .failed) == nil)
    }

    @Test func missingRecordTypeMeansCreateTheAccount() {
        struct LookupError: Error, LocalizedError {
            var errorDescription: String?
        }
        let missing = LookupError(errorDescription: "Did not find record type: Account")
        #expect(GridIdentityLogic.accountLookup(from: missing) == .missing)
        let other = LookupError(errorDescription: "Network unavailable")
        if case .failed = GridIdentityLogic.accountLookup(from: other) {
        } else {
            Issue.record("Expected a failed lookup")
        }
    }

    @Test func missingAccountReusesTheStoredId() {
        let resolved = GridIdentityLogic.accountID(stored: "local", lookup: .missing)
        #expect(resolved?.id == "local")
        #expect(resolved?.isNew == false)
    }

    @Test func conversationIdIgnoresPhoneOrder() {
        let left = GridIdentityLogic.conversationID(accountA: "bbbb", accountB: "aaaa")
        let right = GridIdentityLogic.conversationID(accountA: "aaaa", accountB: "bbbb")
        #expect(left == right)
        #expect(left != nil)
        #expect(GridIdentityLogic.conversationID(accountA: "aaaa", accountB: "aaaa") == nil)
    }

    @Test func pairIdsStayStable() {
        let relationship = GridIdentityLogic.relationshipID(actorAccountID: "a", targetAccountID: "b")
        #expect(relationship == GridIdentityLogic.relationshipID(actorAccountID: "a", targetAccountID: "b"))
        #expect(relationship != GridIdentityLogic.relationshipID(actorAccountID: "b", targetAccountID: "a"))
        #expect(GridIdentityLogic.footstepID(interestID: "hiking", cellKey: "10x20")
                == GridIdentityLogic.footstepID(interestID: "hiking", cellKey: "10x20"))
        #expect(GridIdentityLogic.albumGrantID(ownerAccountID: "owner", viewerAccountID: "viewer")
                != GridIdentityLogic.albumGrantID(ownerAccountID: "viewer", viewerAccountID: "owner"))
    }
}
