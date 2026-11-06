import Foundation
import MapleCoreKit

/// Read-only helpers for Admin Today, Snow Ops and Supervisor Review. Public AppStore API only.
extension AppStore {
    /// Today's routes a crew is working right now, for the Active crews card.
    var todayActiveCrewRoutes: [Route] {
        todayRoutes.filter { $0.state == .inProgress && $0.crewID != nil }
    }

    /// Routes today or upcoming that still need a crew.
    var todayRoutesNeedingCrew: [Route] {
        (todayRoutes + upcomingRoutes).filter(\.needsCrew)
    }

    /// Most recent photos across visit reports, newest first.
    func todayRecentPhotos(limit: Int = 6) -> [(photo: VisitPhoto, propertyID: Property.ID)] {
        let visits = visitRecords
            .filter { $0.kind == .visit && !$0.photos.isEmpty }
            .sorted { $0.date > $1.date }
        var result: [(photo: VisitPhoto, propertyID: Property.ID)] = []
        for visit in visits {
            for photo in visit.photos.sorted(by: { $0.capturedAt > $1.capturedAt }) {
                result.append((photo: photo, propertyID: visit.propertyID))
                if result.count >= limit { return result }
            }
        }
        return result
    }

    /// "Review · 1 of 3" position, when the visit is in the queue.
    func reviewQueuePosition(of visitID: VisitRecord.ID) -> (index: Int, total: Int)? {
        let queue = reviewQueue
        guard let index = queue.firstIndex(where: { $0.id == visitID }) else { return nil }
        return (index: index + 1, total: queue.count)
    }

    /// The next visit to review after this one, if any remain.
    func nextReviewVisit(after visitID: VisitRecord.ID) -> VisitRecord? {
        reviewQueue.first { $0.id != visitID }
    }

    /// People on the crews of the given snow routes (each crew counted once).
    func snowDispatchHeadcount(_ routes: [SnowRoute]) -> Int {
        let crewIDs = Set(routes.compactMap(\.crewID))
        return crewIDs.reduce(0) { total, id in total + (crew(id).map { members(of: $0).count } ?? 0) }
    }
}
