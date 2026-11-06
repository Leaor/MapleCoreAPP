import Foundation

/// Preview fixtures. Every name, address, amount and weather value is sample data, not real records.
/// Times are anchored to the moment the store is created so ETAs and timers feel live.
public struct Fixtures: Sendable {
    public let now: Date
    private let cal = Calendar.current

    public init(now: Date = Date()) {
        // Round to the minute so derived times read cleanly.
        let seconds = cal.component(.second, from: now)
        self.now = now.addingTimeInterval(TimeInterval(-seconds))
    }

    // MARK: Time helpers

    func minutes(_ m: Int) -> Date { now.addingTimeInterval(TimeInterval(m * 60)) }
    func days(_ d: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        let day = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now))!
        // Add as an offset so minute values above 59 roll over (e.g. 5:20 + 120 min).
        return day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }
    var today: Date { cal.startOfDay(for: now) }

    // MARK: IDs

    public enum ID {
        public static let michael = "s-michael", daniel = "s-daniel", marco = "s-marco", priya = "s-priya", luis = "s-luis"
        public static let jordan = "s-jordan", aiden = "s-aiden", kofi = "s-kofi", ben = "s-ben"
        public static let crewA = "c-a", crewB = "c-b", crewC = "c-c", crewD = "c-d"
        public static let islington = "p-islington", humberBay = "p-humber", kingsway = "p-kingsway", riverwood = "p-riverwood"
        public static let kingsview = "p-kingsview", dundas = "p-dundas", royalYork = "p-royalyork", sixPoints = "p-sixpoints"
        public static let lambeth14 = "p-lambeth14", lambeth22 = "p-lambeth22"
        public static let northwest = "cu-northwest", riverwoodCorp = "cu-riverwood", kingswayMgmt = "cu-kingsway", kingsviewOwner = "cu-kingsview"
        public static let dundasStorage = "cu-dundas", humberCorp = "cu-humber", rina = "cu-rina", lambeth22Owner = "cu-lambeth22"
        public static let routeNorth = "r-north", routeLakeshore = "r-lakeshore", routeKingsway = "r-kingsway"
        public static let routeSweep = "r-sweep", routeEarly = "r-early"
        public static let threadSandra = "t-sandra", threadRina = "t-rina", threadCrewA = "t-crewa", threadPriya = "t-priya"
        public static let threadAllCrews = "t-allcrews", threadMichaelDaniel = "t-michael-daniel", threadRiverwood = "t-riverwood"
    }

    // MARK: Accounts

    public static let accounts: [Account] = [
        Account(staffID: ID.michael, displayName: "Michael Chen", firstName: "Michael", initials: "MC", login: "michael@maplecorelawncare.com", roles: [.admin, .field], jobTitle: "Owner", company: "MapleCore LawnCare"),
        Account(staffID: ID.daniel, displayName: "Daniel Reyes", firstName: "Daniel", initials: "DR", login: "daniel@maplecorelawncare.com", roles: [.field], jobTitle: "Crew lead", company: "MapleCore LawnCare"),
        Account(staffID: ID.priya, displayName: "Priya Kaur", firstName: "Priya", initials: "PK", login: "priya@maplecorelawncare.com", roles: [.supervisor], jobTitle: "Crew lead · Supervisor", company: "MapleCore LawnCare")
    ]

    // MARK: People

    public var staff: [StaffMember] {
        let week = [true, true, true, true, true, true, false]
        return [
            StaffMember(id: ID.michael, name: "Michael Chen", initials: "MC", jobTitle: "Owner", crewID: nil, isLead: false, phone: "416-555-0100", email: "michael@maplecorelawncare.com", startYear: 2019, onDutySince: minutes(-190), location: .notShared(lastArrival: nil), availability: week, visitsThisWeek: 0, onTimeRate: 1, photoProofRate: 1, lastShift: "Fri 6:30–5:10"),
            StaffMember(id: ID.daniel, name: "Daniel Reyes", initials: "DR", jobTitle: "Crew lead", crewID: ID.crewA, isLead: true, phone: "416-555-0131", email: "daniel@maplecorelawncare.com", startYear: 2025, onDutySince: minutes(-158), location: .live(place: "Humber Bay Towers", updatedAt: minutes(-1)), availability: week, visitsThisWeek: 31, onTimeRate: 0.94, photoProofRate: 1, lastShift: "Fri 7:00–3:42"),
            StaffMember(id: ID.marco, name: "Marco Silva", initials: "MS", jobTitle: "Crew member", crewID: ID.crewA, isLead: false, phone: "416-555-0132", email: "marco@maplecorelawncare.com", startYear: 2025, onDutySince: minutes(-158), location: .live(place: "Humber Bay Towers", updatedAt: minutes(-2)), availability: week, visitsThisWeek: 29, onTimeRate: 0.93, photoProofRate: 0.98, lastShift: "Fri 7:00–3:42"),
            StaffMember(id: ID.priya, name: "Priya Kaur", initials: "PK", jobTitle: "Crew lead", crewID: ID.crewB, isLead: true, phone: "416-555-0141", email: "priya@maplecorelawncare.com", startYear: 2023, onDutySince: minutes(-150), location: .notShared(lastArrival: minutes(-55)), availability: week, visitsThisWeek: 27, onTimeRate: 0.84, photoProofRate: 0.97, lastShift: "Fri 7:10–4:05"),
            StaffMember(id: ID.luis, name: "Luis Martín", initials: "LM", jobTitle: "Crew member", crewID: ID.crewB, isLead: false, phone: "416-555-0142", email: "luis@maplecorelawncare.com", startYear: 2024, onDutySince: minutes(-150), location: .lastReported(at: minutes(-12)), availability: week, visitsThisWeek: 26, onTimeRate: 0.85, photoProofRate: 0.95, lastShift: "Fri 7:10–4:05"),
            StaffMember(id: ID.jordan, name: "Jordan Tremblay", initials: "JT", jobTitle: "Crew lead", crewID: ID.crewC, isLead: true, phone: "416-555-0151", email: "jordan@maplecorelawncare.com", startYear: 2022, onDutySince: nil, shiftStartsAt: days(0, 11), location: .notShared(lastArrival: nil), availability: week, visitsThisWeek: 24, onTimeRate: 0.93, photoProofRate: 1, lastShift: "Fri 11:00–6:30"),
            StaffMember(id: ID.aiden, name: "Aiden Walsh", initials: "AW", jobTitle: "Crew member", crewID: ID.crewC, isLead: false, phone: "416-555-0152", email: "aiden@maplecorelawncare.com", startYear: 2025, onDutySince: nil, shiftStartsAt: days(0, 11), location: .notShared(lastArrival: nil), availability: week, visitsThisWeek: 22, onTimeRate: 0.92, photoProofRate: 0.99, lastShift: "Fri 11:00–6:30"),
            StaffMember(id: ID.kofi, name: "Kofi Owusu", initials: "KO", jobTitle: "Crew lead", crewID: ID.crewD, isLead: true, phone: "416-555-0161", email: "kofi@maplecorelawncare.com", startYear: 2021, onDutySince: nil, location: .notShared(lastArrival: nil), availability: [true, false, true, true, true, true, false], visitsThisWeek: 18, onTimeRate: 0.97, photoProofRate: 1, lastShift: "Today 5:20–7:58"),
            StaffMember(id: ID.ben, name: "Ben Novak", initials: "BN", jobTitle: "Crew member", crewID: ID.crewD, isLead: false, phone: "416-555-0162", email: "ben@maplecorelawncare.com", startYear: 2024, onDutySince: nil, location: .notShared(lastArrival: nil), availability: [true, false, true, true, true, true, false], visitsThisWeek: 18, onTimeRate: 0.96, photoProofRate: 1, lastShift: "Today 5:20–7:58")
        ]
    }

    public var crews: [Crew] {
        [
            Crew(id: ID.crewA, name: "Crew A", letter: "A", leadID: ID.daniel, memberIDs: [ID.daniel, ID.marco], truck: "Truck 1"),
            Crew(id: ID.crewB, name: "Crew B", letter: "B", leadID: ID.priya, memberIDs: [ID.priya, ID.luis], truck: "Truck 2"),
            Crew(id: ID.crewC, name: "Crew C", letter: "C", leadID: ID.jordan, memberIDs: [ID.jordan, ID.aiden], truck: "Truck 3"),
            Crew(id: ID.crewD, name: "Crew D", letter: "D", leadID: ID.kofi, memberIDs: [ID.kofi, ID.ben], truck: "Truck 4", isSnowReady: true, offDays: [.tuesday])
        ]
    }

    // MARK: Customers & properties

    public var customers: [Customer] {
        [
            Customer(id: ID.northwest, name: "Northwest Health Partners", initials: "NH", isCommercial: true, customerSince: 2024, contacts: [
                Contact(id: "ct-sandra", name: "Sandra Lee", detail: "Facilities manager · prefers messages", phone: "416-555-0199", email: "sandra.lee@example.com", isPrimary: true),
                Contact(id: "ct-ap", name: "Accounts Payable", detail: "Receives invoices by email", email: "ap@example.com")
            ]),
            Customer(id: ID.riverwoodCorp, name: "Riverwood Condo Corp.", initials: "RC", isCommercial: true, customerSince: 2023, contacts: [
                Contact(id: "ct-board", name: "Riverwood Board", detail: "Property manager · email", email: "board@example.com", isPrimary: true)
            ]),
            Customer(id: ID.kingswayMgmt, name: "Kingsway Plaza Mgmt.", initials: "KP", isCommercial: true, customerSince: 2022, contacts: [
                Contact(id: "ct-kp", name: "Alan Brooks", detail: "Plaza manager", phone: "416-555-0177", isPrimary: true)
            ]),
            Customer(id: ID.kingsviewOwner, name: "48 Kingsview Blvd", initials: "KB", isCommercial: false, customerSince: 2025, contacts: [
                Contact(id: "ct-kb", name: "Homeowner", detail: "Prefers phone", phone: "416-555-0144", isPrimary: true)
            ]),
            Customer(id: ID.dundasStorage, name: "Dundas West Storage", initials: "DW", isCommercial: true, customerSince: 2021, contacts: [
                Contact(id: "ct-dw", name: "Site office", detail: "Open 7–7", phone: "416-555-0188", isPrimary: true)
            ]),
            Customer(id: ID.humberCorp, name: "Humber Bay Towers Corp.", initials: "HB", isCommercial: true, customerSince: 2024, contacts: [
                Contact(id: "ct-hb", name: "Concierge", detail: "Front desk", phone: "416-555-0122", isPrimary: true)
            ]),
            Customer(id: ID.rina, name: "Rina Patel", initials: "RP", isCommercial: false, customerSince: 2025, contacts: [
                Contact(id: "ct-rina", name: "Rina Patel", detail: "Homeowner", phone: "416-555-0166", isPrimary: true)
            ]),
            Customer(id: ID.lambeth22Owner, name: "22 Lambeth Rd", initials: "LR", isCommercial: false, customerSince: 2026, contacts: [
                Contact(id: "ct-l22", name: "Homeowner", detail: "Email preferred", email: "owner22@example.com", isPrimary: true)
            ])
        ]
    }

    public var properties: [Property] {
        let contractStart = days(-178)
        let contractEnd = days(186)
        return [
            Property(id: ID.islington, name: "Islington Medical Centre", address: "1 Kipling Ave", city: "Etobicoke", kind: .commercial, descriptor: "Commercial", customerID: ID.northwest, services: [.lawnCare, .fallCleanup, .snowPlowing, .salting], primaryService: "Fall cleanup", frequency: .weekly, preferredDay: .monday, assignedCrewID: ID.crewA, accessNotes: "Rear lot off Kipling. No blowers near entrance 9–5. Salt bin key in lockbox by loading door.", notes: "Customer prefers leaves bagged, not mulched. Keep the memorial garden by the east entrance untouched.", notesUpdatedBy: "Michael", notesUpdatedAt: days(-23), measurements: .init(lawnSqM: 1150, gardenBedsSqM: 180, parkingSqM: 2400, walkwaysM: 140), equipment: ["Zero-turn mower", "Backpack blowers ×2", "Leaf vacuum trailer", "Edger"], contractStart: contractStart, contractEnd: contractEnd, latitude: 43.6375, longitude: -79.5302),
            Property(id: ID.humberBay, name: "Humber Bay Towers", address: "2200 Lake Shore Blvd W", city: "Etobicoke", kind: .condo, descriptor: "Condo", customerID: ID.humberCorp, services: [.lawnCare, .fallCleanup, .snowPlowing], primaryService: "Fall cleanup", frequency: .weekly, preferredDay: .monday, assignedCrewID: ID.crewA, accessNotes: "Check in with concierge. Side gate code 4471.", measurements: .init(lawnSqM: 2200, gardenBedsSqM: 340, parkingSqM: 0, walkwaysM: 260), equipment: ["Backpack blowers ×2", "Leaf vacuum trailer"], contractStart: contractStart, contractEnd: contractEnd, latitude: 43.6262, longitude: -79.4786),
            Property(id: ID.kingsway, name: "Kingsway Plaza", address: "2950 Bloor St W", city: "Etobicoke", kind: .retail, descriptor: "Retail", customerID: ID.kingswayMgmt, services: [.lawnCare, .salting], primaryService: "Weekly mowing", frequency: .weekly, preferredDay: .monday, assignedCrewID: ID.crewA, accessNotes: "Park behind the bank. Avoid patio during lunch.", measurements: .init(lawnSqM: 900, gardenBedsSqM: 120, parkingSqM: 3200, walkwaysM: 180), equipment: ["Zero-turn mower", "Edger"], contractStart: contractStart, contractEnd: contractEnd, latitude: 43.6496, longitude: -79.5111),
            Property(id: ID.riverwood, name: "Riverwood Townhomes", address: "30 Riverwood Pkwy", city: "Etobicoke", kind: .condo, descriptor: "30 units · Condo corp.", customerID: ID.riverwoodCorp, services: [.lawnCare, .fallCleanup, .snowPlowing, .salting], primaryService: "Leaf removal", frequency: .biweekly, preferredDay: .monday, assignedCrewID: ID.crewA, accessNotes: "Gate code changed — ask board. Visitor parking only, not the fire lane.", notes: "Board wants leaves bagged, not mulched.", notesUpdatedBy: "Priya", notesUpdatedAt: days(-3), measurements: .init(lawnSqM: 3100, gardenBedsSqM: 420, parkingSqM: 1800, walkwaysM: 520), equipment: ["Backpack blowers ×2", "Leaf vacuum trailer", "Tarps"], contractStart: contractStart, contractEnd: contractEnd, latitude: 43.6431, longitude: -79.5207),
            Property(id: ID.kingsview, name: "48 Kingsview Blvd", address: "48 Kingsview Blvd", city: "Etobicoke", kind: .residential, descriptor: "Residential", customerID: ID.kingsviewOwner, services: [.fallCleanup], primaryService: "Fall cleanup", frequency: .seasonal, preferredDay: .tuesday, assignedCrewID: ID.crewA, accessNotes: "Side gate unlocked. Bins in garage.", measurements: .init(lawnSqM: 420, gardenBedsSqM: 60), equipment: ["Backpack blowers ×2"], latitude: 43.6905, longitude: -79.5462),
            Property(id: ID.dundas, name: "Dundas West Storage", address: "3100 Dundas St W", city: "Toronto", kind: .commercial, descriptor: "Commercial", customerID: ID.dundasStorage, services: [.snowPlowing, .salting], primaryService: "Plow & salt", frequency: .onCall, preferredDay: .monday, assignedCrewID: ID.crewD, accessNotes: "Gate locked before 7 AM — call site office.", measurements: .init(parkingSqM: 5400, walkwaysM: 90), equipment: ["Plow truck", "Salt spreader"], contractStart: contractStart, contractEnd: contractEnd, openIssues: 1, latitude: 43.6655, longitude: -79.4752),
            Property(id: ID.royalYork, name: "Royal York Clinic", address: "1436 Royal York Rd", city: "Etobicoke", kind: .commercial, descriptor: "Commercial", customerID: ID.northwest, services: [.lawnCare, .fallCleanup, .salting], primaryService: "Fall cleanup", frequency: .weekly, preferredDay: .monday, assignedCrewID: ID.crewA, accessNotes: "Staff lot at rear.", measurements: .init(lawnSqM: 600, gardenBedsSqM: 90, parkingSqM: 1200, walkwaysM: 70), equipment: ["Backpack blowers ×2"], contractStart: contractStart, contractEnd: contractEnd, latitude: 43.6829, longitude: -79.5195),
            Property(id: ID.sixPoints, name: "Six Points Lab Annex", address: "5230 Dundas St W", city: "Etobicoke", kind: .commercial, descriptor: "Commercial", customerID: ID.northwest, services: [.lawnCare, .salting], primaryService: "Mowing", frequency: .weekly, preferredDay: .monday, assignedCrewID: ID.crewA, accessNotes: "Badge access at loading dock.", measurements: .init(lawnSqM: 400, gardenBedsSqM: 40, parkingSqM: 900, walkwaysM: 60), equipment: ["Zero-turn mower"], contractStart: contractStart, contractEnd: contractEnd, latitude: 43.6440, longitude: -79.5366),
            Property(id: ID.lambeth14, name: "14 Lambeth Rd", address: "14 Lambeth Rd", city: "Etobicoke", kind: .residential, descriptor: "Residential", customerID: ID.rina, services: [.lawnCare, .fallCleanup], primaryService: "Fall cleanup", frequency: .biweekly, preferredDay: .monday, assignedCrewID: ID.crewA, accessNotes: "Dog in backyard, keep gate latched.", measurements: .init(lawnSqM: 380, gardenBedsSqM: 50), equipment: ["Backpack blowers ×2"], latitude: 43.6588, longitude: -79.5170),
            Property(id: ID.lambeth22, name: "22 Lambeth Rd", address: "22 Lambeth Rd", city: "Etobicoke", kind: .residential, descriptor: "Residential", customerID: ID.lambeth22Owner, services: [.lawnCare], primaryService: "Mowing", frequency: .biweekly, preferredDay: .tuesday, assignedCrewID: ID.crewC, accessNotes: "Front lawn only.", measurements: .init(lawnSqM: 300), equipment: ["Push mower"], latitude: 43.6592, longitude: -79.5179)
        ]
    }

    // MARK: Routes

    private func tasks(_ prefix: String, _ titles: [String], done: Bool = false, addedTodayIndex: Int? = nil) -> [VisitTask] {
        titles.enumerated().map { i, t in VisitTask(id: "\(prefix)-t\(i)", title: t, isDone: done, addedToday: i == addedTodayIndex) }
    }

    public var routes: [Route] {
        // Route North: Crew A, stops 1–5 done, stop 6 (Islington) next.
        let northStart = minutes(-158)
        var north: [RouteStop] = []
        let northDone: [(String, String, Int)] = [
            (ID.kingsway, "Weekly mowing", 38), (ID.royalYork, "Fall cleanup", 26), (ID.sixPoints, "Mowing", 18),
            (ID.lambeth14, "Fall cleanup", 21), (ID.humberBay, "Fall cleanup", 40)
        ]
        var cursor = northStart.addingTimeInterval(10 * 60)
        for (i, item) in northDone.enumerated() {
            let finished = cursor.addingTimeInterval(TimeInterval(item.2 * 60))
            north.append(RouteStop(id: "north-\(i + 1)", propertyID: item.0, serviceName: item.1, estimatedMinutes: item.2 + 2, eta: cursor, status: .done, tasks: tasks("north-\(i + 1)", ["Main service", "Clean up & blow off hard surfaces"], done: true), completedAt: finished, actualMinutes: item.2, startedAt: cursor))
            cursor = finished.addingTimeInterval(7 * 60)
        }
        north.append(RouteStop(id: "north-6", propertyID: ID.islington, serviceName: "Leaf removal", estimatedMinutes: 45, eta: minutes(8), status: .pending, priority: .high, tasks: tasks("north-6", ["Blow & bag leaves — front beds", "Clear lot edges & drains", "Side gate leaves"], addedTodayIndex: 2)))
        north.append(RouteStop(id: "north-7", propertyID: ID.riverwood, serviceName: "Leaf removal", estimatedMinutes: 70, eta: minutes(73), tasks: tasks("north-7", ["Leaves — common areas", "Bag at curb", "Blow walkways"])))
        north.append(RouteStop(id: "north-8", propertyID: ID.kingsview, serviceName: "Fall cleanup", estimatedMinutes: 25, eta: minutes(153), tasks: tasks("north-8", ["Front & back beds", "Bag leaves"])))
        north.append(RouteStop(id: "north-9", propertyID: ID.lambeth22, serviceName: "Mowing", estimatedMinutes: 20, eta: minutes(186), tasks: tasks("north-9", ["Mow front lawn", "Edge walkway"])))

        // Route Lakeshore: Crew B, 2 of 8 done, running 20 min late.
        let lakeProps = [ID.humberBay, ID.kingsway, ID.riverwood, ID.royalYork, ID.sixPoints, ID.islington, ID.lambeth14, ID.kingsview]
        let lakeshore: [RouteStop] = lakeProps.enumerated().map { i, pid in
            RouteStop(id: "lake-\(i + 1)", propertyID: pid, serviceName: "Grounds care", estimatedMinutes: 35, eta: minutes(-90 + i * 45 + 20), status: i < 2 ? .done : (i == 2 ? .delayed : .pending), tasks: tasks("lake-\(i + 1)", ["Grounds care", "Blow walkways"], done: i < 2), completedAt: i < 2 ? minutes(-90 + i * 45 + 35) : nil, actualMinutes: i < 2 ? 34 : nil, delayMinutes: i >= 2 ? 20 : 0)
        }

        // Kingsway Residential: Crew C, starts 11:00.
        let kingsProps = [ID.islington, ID.riverwood, ID.kingsview, ID.dundas, ID.lambeth22, ID.lambeth14, ID.royalYork]
        let kingsMinutes = [45, 70, 25, 30, 20, 20, 40]
        let kingsStart = days(0, 11)
        var kc = kingsStart
        let kingsway: [RouteStop] = kingsProps.enumerated().map { i, pid in
            defer { kc = kc.addingTimeInterval(TimeInterval((kingsMinutes[i] + 8) * 60)) }
            return RouteStop(id: "kings-\(i + 1)", propertyID: pid, serviceName: "Leaf removal", estimatedMinutes: kingsMinutes[i], eta: kc, priority: i == 0 ? .high : .normal, tasks: tasks("kings-\(i + 1)", ["Leaf removal", "Bag at curb"]))
        }

        // Commercial Sweep: tomorrow, needs a crew.
        let sweepProps = [ID.kingsway, ID.dundas, ID.sixPoints, ID.royalYork, ID.islington, ID.humberBay]
        let sweep: [RouteStop] = sweepProps.enumerated().map { i, pid in
            RouteStop(id: "sweep-\(i + 1)", propertyID: pid, serviceName: "Parking lot sweep", estimatedMinutes: 30, eta: days(1, 8, i * 35), tasks: tasks("sweep-\(i + 1)", ["Sweep lot", "Empty debris"]))
        }

        // Early Commercial: Crew D, complete today 5:20–7:58.
        let earlyProps = [ID.dundas, ID.kingsway, ID.sixPoints, ID.royalYork, ID.islington, ID.humberBay]
        let early: [RouteStop] = earlyProps.enumerated().map { i, pid in
            RouteStop(id: "early-\(i + 1)", propertyID: pid, serviceName: "Lot sweep & litter", estimatedMinutes: 25, eta: days(0, 5, 20 + i * 24), status: .done, tasks: tasks("early-\(i + 1)", ["Sweep lot"], done: true), completedAt: days(0, 5, 40 + i * 24), actualMinutes: 20, startedAt: days(0, 5, 20 + i * 24))
        }

        var result = [
            Route(id: ID.routeNorth, name: "Route North", serviceSummary: "Mowing & fall cleanup", date: today, startTime: northStart, crewID: ID.crewA, stops: north, state: .inProgress, driveMinutes: 64, distanceKm: 41),
            Route(id: ID.routeLakeshore, name: "Route Lakeshore", serviceSummary: "Condo grounds", date: today, startTime: minutes(-150), crewID: ID.crewB, stops: lakeshore, state: .inProgress, delayMinutes: 20, driveMinutes: 70, distanceKm: 36),
            Route(id: ID.routeKingsway, name: "Kingsway Residential", serviceSummary: "Leaf removal", date: today, startTime: kingsStart, crewID: ID.crewC, stops: kingsway, state: .scheduled, driveMinutes: 52, distanceKm: 38),
            Route(id: ID.routeSweep, name: "Commercial Sweep", serviceSummary: "Parking lots", date: days(1), startTime: days(1, 8), crewID: nil, stops: sweep, state: .scheduled, driveMinutes: 40, distanceKm: 29),
            Route(id: ID.routeEarly, name: "Early Commercial", serviceSummary: "Lot sweep & litter", date: today, startTime: days(0, 5, 20), crewID: ID.crewD, stops: early, state: .completed, driveMinutes: 37, distanceKm: 22, finishedAt: days(0, 7, 58), issuesReported: ["Dundas West Storage — irrigation head broken near loading bay"], reviewedCount: 2, photoCount: 42, plannedMinutes: 150)
        ]
        result.append(contentsOf: historyRoutes)
        return result
    }

    private var historyRoutes: [Route] {
        func past(_ id: String, _ name: String, _ crew: String, day: Int, stops: Int, done: Int, minutes: Int, late: Int = 0) -> Route {
            let start = days(day, 7, 0)
            let s: [RouteStop] = (0..<stops).map { i in
                RouteStop(id: "\(id)-\(i + 1)", propertyID: [ID.islington, ID.kingsway, ID.riverwood, ID.humberBay, ID.royalYork, ID.sixPoints, ID.lambeth14, ID.kingsview, ID.dundas][i % 9], serviceName: "Service", estimatedMinutes: 30, eta: start.addingTimeInterval(TimeInterval(i * 40 * 60)), status: i < done ? .done : .skipped, completedAt: i < done ? start.addingTimeInterval(TimeInterval((i * 40 + 30) * 60)) : nil, actualMinutes: i < done ? 30 : nil, skipReason: i < done ? nil : "Gate locked")
            }
            return Route(id: id, name: name, serviceSummary: "Scheduled service", date: days(day), startTime: start, crewID: crew, stops: s, state: .completed, delayMinutes: late, finishedAt: start.addingTimeInterval(TimeInterval(minutes * 60)), reviewedCount: done, photoCount: done * 6, plannedMinutes: minutes - late)
        }
        return [
            past("h-north-3", "Route North", ID.crewA, day: -3, stops: 9, done: 9, minutes: 372),
            past("h-lake-3", "Route Lakeshore", ID.crewB, day: -3, stops: 8, done: 7, minutes: 348),
            past("h-kings-3", "Kingsway Residential", ID.crewC, day: -3, stops: 7, done: 7, minutes: 271),
            past("h-north-4", "Route North", ID.crewA, day: -4, stops: 9, done: 9, minutes: 400, late: 28),
            past("h-sweep-4", "Commercial Sweep", ID.crewD, day: -4, stops: 6, done: 6, minutes: 185),
            past("h-lake-4", "Route Lakeshore", ID.crewB, day: -4, stops: 8, done: 8, minutes: 322)
        ]
    }

    // MARK: Visit records

    private func photoSet(_ prefix: String, before: Int, work: Int = 0, after: Int, at date: Date, offline: Int = 0) -> [VisitPhoto] {
        let angles = ["Front beds", "Parking lot", "Side gate", "Walkway", "Rear lot", "Entrance"]
        var photos: [VisitPhoto] = []
        var n = 0
        func add(_ kind: PhotoKind, _ count: Int, _ offset: Int) {
            for i in 0..<count {
                let captured = date.addingTimeInterval(TimeInterval((offset + i) * 60))
                let isOffline = n < offline
                photos.append(VisitPhoto(id: "\(prefix)-\(kind.rawValue)-\(i)", kind: kind, angle: angles[i % angles.count], caption: "", capturedAt: captured, receivedAt: isOffline ? captured.addingTimeInterval(1800) : captured.addingTimeInterval(40), source: .inAppCamera, upload: .uploaded, swatch: n % 6))
                n += 1
            }
        }
        add(.before, before, 0)
        add(.work, work, 15)
        add(.after, after, 40)
        return photos
    }

    public var visitRecords: [VisitRecord] {
        let kingswayArrive = minutes(-136)
        return [
            // Awaiting review
            VisitRecord(id: "v-kingsway-today", propertyID: ID.kingsway, kind: .visit, title: "Weekly mowing", crewID: ID.crewA, crewNames: "Daniel R., Marco S.", date: kingswayArrive, arrivedAt: kingswayArrive, workStart: kingswayArrive.addingTimeInterval(120), workEnd: kingswayArrive.addingTimeInterval(38 * 60), workMinutes: 36, pausedMinutes: 2, estimateMinutes: 40, receivedAt: kingswayArrive.addingTimeInterval(40 * 60 + 12), photos: photoSet("vk", before: 3, after: 3, at: kingswayArrive, offline: 2), notes: "Edged along the Bloor frontage. Left clippings off the patio. Sprinkler head by stall 12 is leaning — didn't touch it.", review: .awaiting, arrivalVerified: true),
            VisitRecord(id: "v-dundas-early", propertyID: ID.dundas, kind: .visit, title: "Lot sweep & litter", crewID: ID.crewD, crewNames: "Kofi O., Ben N.", date: days(0, 5, 20), arrivedAt: days(0, 5, 20), workStart: days(0, 5, 22), workEnd: days(0, 5, 42), workMinutes: 20, estimateMinutes: 25, receivedAt: days(0, 5, 44), photos: photoSet("vd", before: 3, after: 4, at: days(0, 5, 20)), notes: "Irrigation head broken near loading bay — flagged as issue.", review: .awaiting, arrivalVerified: true),
            VisitRecord(id: "v-royal-early", propertyID: ID.royalYork, kind: .visit, title: "Lot sweep & litter", crewID: ID.crewD, crewNames: "Kofi O., Ben N.", date: days(0, 6, 32), arrivedAt: days(0, 6, 32), workStart: days(0, 6, 33), workEnd: days(0, 6, 53), workMinutes: 20, estimateMinutes: 25, receivedAt: days(0, 6, 55), photos: photoSet("vr", before: 3, after: 3, at: days(0, 6, 32)), notes: "All clear. Two bags of litter removed.", review: .awaiting, arrivalVerified: true),
            // Islington history
            VisitRecord(id: "v-isl-1", propertyID: ID.islington, kind: .visit, title: "Fall cleanup", crewID: ID.crewA, crewNames: "Daniel R., Marco S.", date: days(-7, 9, 41), arrivedAt: days(-7, 9, 41), workStart: days(-7, 9, 43), workEnd: days(-7, 10, 23), workMinutes: 42, pausedMinutes: 0, estimateMinutes: 45, receivedAt: days(-7, 10, 25), photos: photoSet("vi1", before: 3, work: 1, after: 4, at: days(-7, 9, 41)), notes: "Bagged 12 bags. Memorial garden untouched.", review: .approved, reviewedBy: "Michael", reviewedAt: days(-7, 13, 0), arrivalVerified: true),
            VisitRecord(id: "v-isl-note", propertyID: ID.islington, kind: .note, title: "Note added", detail: "“Customer prefers leaves bagged.” — Michael", date: days(-12, 14, 0), review: .approved),
            VisitRecord(id: "v-isl-issue", propertyID: ID.islington, kind: .issue, title: "Issue: irrigation leak", detail: "Reported by Marco S. with 2 photos · broken head near loading bay", crewID: ID.crewA, date: days(-14, 10, 5), photos: photoSet("vii", before: 0, work: 2, after: 0, at: days(-14, 10, 5)), review: .approved, resolvedAt: days(-11)),
            VisitRecord(id: "v-isl-2", propertyID: ID.islington, kind: .visit, title: "Mowing & edging", crewID: ID.crewA, crewNames: "Daniel R., Marco S.", date: days(-14, 9, 30), arrivedAt: days(-14, 9, 30), workStart: days(-14, 9, 31), workEnd: days(-14, 10, 9), workMinutes: 38, estimateMinutes: 40, receivedAt: days(-14, 10, 11), photos: photoSet("vi2", before: 3, after: 3, at: days(-14, 9, 30)), notes: "Edged all walkways.", review: .approved, reviewedBy: "Michael", reviewedAt: days(-14, 15, 0), arrivalVerified: true),
            VisitRecord(id: "v-isl-skip", propertyID: ID.islington, kind: .skipped, title: "Mowing", detail: "Rain day · rescheduled", date: days(-21), review: .approved)
        ]
    }

    // MARK: Documents

    public var documents: [PropertyDocument] {
        [
            PropertyDocument(id: "d-agreement", propertyID: ID.islington, title: "2026–27 Service Agreement", detail: "Lawn, fall cleanup, snow & salt · 12 pages · PDF", kind: .pdf, tag: "Signed", isFeatured: true),
            PropertyDocument(id: "d-siteplan", propertyID: ID.islington, title: "Site plan & snow piling map", detail: "Updated · Michael", kind: .pdf),
            PropertyDocument(id: "d-insurance", propertyID: ID.islington, title: "Certificate of insurance", detail: "For customer records", kind: .pdf, tag: "Renew Dec 1"),
            PropertyDocument(id: "d-q212", propertyID: ID.islington, title: "Quote Q-212 · Spring aeration", detail: "Sent", kind: .quote, tag: "Awaiting", quoteID: "q-212"),
            PropertyDocument(id: "d-report", propertyID: ID.islington, title: "Visit report · Fall cleanup", detail: "8 photos · auto-generated", kind: .report, visitID: "v-isl-1")
        ]
    }

    // MARK: Messages

    public var threads: [MessageThread] {
        [
            MessageThread(id: ID.threadSandra, kind: .customer, title: "Sandra Lee", initials: "SL", subtitle: "Customer · Northwest Health", customerID: ID.northwest, propertyID: ID.islington, unreadCount: 1, messages: [
                Message(id: "m-s1", authorName: "Sandra Lee", authorInitials: "SL", authorID: nil, text: "Hi — can the crew also clear the leaves along the side gate this week? It's getting slippery.", sentAt: days(-1, 16, 18), visibility: .customer, attachments: [Attachment(id: "a-img2041", kind: .photo, name: "IMG_2041", detail: "Side gate", swatch: 2)]),
                Message(id: "m-s2", authorName: "Michael", authorInitials: "MC", authorID: ID.michael, text: "Added side gate to today's visit, +10 min.", sentAt: days(-1, 16, 30), visibility: .internal)
            ], quickReplies: ["Crew is on the way", "Done — photos attached", "We'll confirm a time"], visibleToField: false),
            MessageThread(id: ID.threadRina, kind: .customer, title: "Rina Patel", initials: "RP", subtitle: "Customer · 14 Lambeth Rd", customerID: ID.rina, propertyID: ID.lambeth14, unreadCount: 1, isUrgent: true, messages: [
                Message(id: "m-r1", authorName: "Rina Patel", authorInitials: "RP", authorID: nil, text: "Branch down across driveway", sentAt: minutes(-12), visibility: .customer, attachments: [Attachment(id: "a-branch", kind: .photo, name: "Photo", detail: "Driveway", swatch: 4)])
            ], quickReplies: ["We'll send a crew today", "Can you send another photo?", "We'll confirm a time"]),
            MessageThread(id: ID.threadCrewA, kind: .crew, title: "Crew A", initials: "A", subtitle: "Daniel, Marco, you", crewID: ID.crewA, unreadCount: 1, messages: [
                Message(id: "m-a1", authorName: "Michael", authorInitials: "MC", authorID: ID.michael, text: "Morning. Islington Medical moved up — they want the side gate cleared too, +10 min.", sentAt: minutes(-95), visibility: .internal),
                Message(id: "m-a2", authorName: "Daniel", authorInitials: "DR", authorID: ID.daniel, text: "Got it. We'll hit it after Humber Bay.", sentAt: minutes(-92), visibility: .internal),
                Message(id: "m-a3", authorName: "Daniel", authorInitials: "DR", authorID: ID.daniel, text: "Daniel started visit · Humber Bay Towers", sentAt: minutes(-60), visibility: .internal, isSystemEvent: true),
                Message(id: "m-a4", authorName: "Marco", authorInitials: "MS", authorID: ID.marco, text: "Side gate was open when we arrived — closed it.", sentAt: minutes(-36), visibility: .internal, propertyTag: "Humber Bay Towers")
            ], visibleToField: true),
            MessageThread(id: ID.threadPriya, kind: .direct, title: "Priya Kaur", initials: "PK", subtitle: "Crew lead · Crew B", crewID: ID.crewB, unreadCount: 1, messages: [
                Message(id: "m-p1", authorName: "Priya", authorInitials: "PK", authorID: ID.priya, text: "Running 20 late — Gardiner is backed up", sentAt: minutes(-49), visibility: .internal)
            ]),
            MessageThread(id: ID.threadAllCrews, kind: .announcement, title: "All crews", initials: "All", subtitle: "Announcement · 11 people", messages: [
                Message(id: "m-all1", authorName: "Michael", authorInitials: "MC", authorID: ID.michael, text: "Snow watch tonight — standby from 2 AM. You'll get a dispatch alert if the trigger is reached.", sentAt: minutes(-71), visibility: .internal, delivery: .seenBy("9 of 11"))
            ], visibleToField: true),
            MessageThread(id: ID.threadMichaelDaniel, kind: .direct, title: "Michael", initials: "MC", subtitle: "Manager", messages: [
                Message(id: "m-md1", authorName: "Michael", authorInitials: "MC", authorID: ID.michael, text: "Can you take Truck 1 home tonight?", sentAt: minutes(-115), visibility: .internal)
            ], visibleToField: true, visibleToAdmin: false),
            MessageThread(id: ID.threadRiverwood, kind: .property, title: "Riverwood Townhomes", initials: "RT", subtitle: "Property notes · internal", propertyID: ID.riverwood, messages: [
                Message(id: "m-rv1", authorName: "Priya", authorInitials: "PK", authorID: ID.priya, text: "Board wants leaves bagged, not mulched", sentAt: days(-3, 15, 20), visibility: .internal)
            ], visibleToField: true)
        ]
    }

    // MARK: Business

    public var quotes: [Quote] {
        [
            Quote(id: "q-214", number: "Q-214", customerID: ID.riverwoodCorp, propertyID: ID.riverwood, title: "Snow & ice season 2026–27", division: .lawnCare, status: .viewed, sentAt: days(-2, 10), expiresAt: days(12), lineItems: [
                LineItem(id: "li-1", title: "Seasonal plowing — lanes & driveways", detail: "Nov 15 – Apr 15", quantity: 1, unitPrice: 9600, unit: "season"),
                LineItem(id: "li-2", title: "Walkway shovelling & salting", detail: "30 units", quantity: 1, unitPrice: 3800, unit: "season"),
                LineItem(id: "li-3", title: "Bulk salt application", quantity: 20, unitPrice: 70, unit: "visit"),
                LineItem(id: "li-4", title: "Snow haul-away", detail: "Billed hourly if needed", quantity: 1, unitPrice: 185, unit: "h", isOptional: true)
            ]),
            Quote(id: "q-212", number: "Q-212", customerID: ID.northwest, propertyID: ID.islington, title: "Spring aeration & overseed", division: .lawnCare, status: .sent, sentAt: days(-6, 11), expiresAt: days(24), lineItems: [
                LineItem(id: "li-5", title: "Core aeration", quantity: 1, unitPrice: Decimal(string: "617.70")!, unit: "visit"),
                LineItem(id: "li-6", title: "Overseed — premium mix", quantity: 1, unitPrice: 400, unit: "visit")
            ]),
            Quote(id: "q-215", number: "Q-215", customerID: ID.lambeth22Owner, propertyID: ID.lambeth22, title: "Tree limb removal & haul-away", division: .lawnCare, status: .viewed, sentAt: days(-1, 14), expiresAt: days(7), lineItems: [
                LineItem(id: "li-7", title: "Limb removal & haul-away", quantity: 1, unitPrice: Decimal(string: "371.68")!, unit: "job")
            ]),
            Quote(id: "q-216", number: "Q-216", customerID: ID.kingswayMgmt, propertyID: ID.kingsway, title: "Interlock walkway repair", division: .construction, status: .draft, lineItems: [
                LineItem(id: "li-8", title: "Lift & relay interlock — 22 m²", quantity: 1, unitPrice: Decimal(string: "4286.73")!, unit: "job"),
                LineItem(id: "li-9", title: "Polymeric sand & compaction", quantity: 1, unitPrice: 1200, unit: "job")
            ]),
            Quote(id: "q-209", number: "Q-209", customerID: ID.humberCorp, propertyID: ID.humberBay, title: "Snow & salt season 2026–27", division: .lawnCare, status: .approved, sentAt: days(-20), approvedAt: days(-9), lineItems: [
                LineItem(id: "li-10", title: "Seasonal snow & salt contract", quantity: 1, unitPrice: Decimal(string: "8796.46")!, unit: "season")
            ]),
            Quote(id: "q-208", number: "Q-208", customerID: ID.kingsviewOwner, propertyID: ID.kingsview, title: "Garden bed refresh", division: .lawnCare, status: .declined, sentAt: days(-16), lineItems: [
                LineItem(id: "li-11", title: "Mulch & edging — front beds", quantity: 1, unitPrice: Decimal(string: "566.37")!, unit: "job")
            ])
        ]
    }

    public var invoices: [Invoice] {
        [
            Invoice(id: "inv-1047", number: "INV-1047", customerID: ID.riverwoodCorp, billToName: "Riverwood Condo Corp.", propertyID: ID.riverwood, title: "September service", issuedAt: days(-36), sentAt: days(-36), viewedAt: days(-30), dueDate: days(-6), lineItems: [
                LineItem(id: "il-1", title: "Grounds care · September", detail: "4 visits", quantity: 1, unitPrice: Decimal(string: "2134.96")!, unit: "month")
            ], reviewedVisitCount: 4),
            Invoice(id: "inv-1048", number: "INV-1048", customerID: ID.northwest, billToName: "Northwest Health Partners", propertyID: ID.islington, title: "Islington Medical", issuedAt: today, sentAt: today, dueDate: days(20), lineItems: [
                LineItem(id: "il-2", title: "Weekly fall cleanup", detail: "Islington Medical", quantity: 4, unitPrice: 380, unit: "visit"),
                LineItem(id: "il-3", title: "Side gate leaf clearing", detail: "Add-on requested by customer", quantity: 1, unitPrice: 80, unit: "job")
            ], reviewedVisitCount: 4),
            Invoice(id: "inv-1045", number: "INV-1045", customerID: ID.kingswayMgmt, billToName: "Kingsway Plaza Mgmt.", propertyID: ID.kingsway, title: "October service", issuedAt: days(-10), sentAt: days(-10), viewedAt: days(-8), dueDate: days(10), lineItems: [
                LineItem(id: "il-4", title: "October service", quantity: 1, unitPrice: 2700, unit: "month")
            ], reviewedVisitCount: 4),
            Invoice(id: "inv-1046", number: "INV-1046", customerID: ID.kingsviewOwner, billToName: "48 Kingsview Blvd", propertyID: ID.kingsview, title: "Fall cleanup", issuedAt: days(-12), sentAt: days(-12), viewedAt: days(-11), dueDate: days(3), lineItems: [
                LineItem(id: "il-5", title: "Fall cleanup", quantity: 1, unitPrice: 420, unit: "job")
            ], payments: [Payment(id: "pay-1", amount: Decimal(string: "474.60")!, method: "e-Transfer", receivedAt: days(-4))], reviewedVisitCount: 1),
            Invoice(id: "inv-1044", number: "INV-1044", customerID: ID.dundasStorage, billToName: "Dundas West Storage", propertyID: ID.dundas, title: "Salting prepay", issuedAt: days(-20), sentAt: days(-20), viewedAt: days(-19), dueDate: days(-5), lineItems: [
                LineItem(id: "il-6", title: "Salting prepay", quantity: 1, unitPrice: 1100, unit: "season")
            ], payments: [Payment(id: "pay-2", amount: 1243, method: "Cheque", receivedAt: days(-8))]),
            Invoice(id: "inv-1019", number: "INV-1019", customerID: ID.northwest, billToName: "Northwest Health Partners", propertyID: ID.islington, title: "September", issuedAt: days(-40), sentAt: days(-40), viewedAt: days(-39), dueDate: days(-20), lineItems: [
                LineItem(id: "il-7", title: "Weekly mowing", quantity: 4, unitPrice: 380, unit: "visit")
            ], payments: [Payment(id: "pay-3", amount: Decimal(string: "1717.60")!, method: "e-Transfer", receivedAt: days(-25))], reviewedVisitCount: 4)
        ]
    }

    // MARK: Snow, weather, sync

    public var snowEvent: SnowEvent {
        SnowEvent(number: 7, startedAt: minutes(-170), groundCm: 9, temperatureC: -6, condition: "heavy snow", hourlyRate: [1.2, 1.5, 1.8, 2.0, 1.6, 1.1, 0.6], forecast: "4–6 cm more by 7 AM, then tapering.", warning: "Freezing rain 5–9 AM. Plan a second salt pass on priority lots before opening.", priorityDone: 12, priorityTotal: 14, priorityDeadline: "7:00 AM", allDone: 38, allTotal: 64, saltUsedTonnes: 6.2, saltTotalTonnes: 14, triggerCm: 2, triggerReachedAt: minutes(-170), newlyTriggeredCount: 54, routes: [
            SnowRoute(id: "sr-1", code: "S1", name: "Commercial priority", crewID: ID.crewD, propertyCount: 14, completed: 12, estimatedMinutes: 240, isDispatched: true, workDetail: "plow + salt"),
            SnowRoute(id: "sr-2", code: "S2", name: "Lakeshore condos", crewID: ID.crewB, propertyCount: 18, completed: 9, estimatedMinutes: 300, behindMinutes: 30, isDispatched: true),
            SnowRoute(id: "sr-3", code: "S3", name: "Residential north", crewID: ID.crewA, propertyCount: 32, estimatedMinutes: 270, isDispatched: false, unitLabel: "driveways"),
            SnowRoute(id: "sr-4", code: "S4", name: "Walkways & salt only", crewID: ID.crewC, propertyCount: 22, estimatedMinutes: 170, isDispatched: false),
            SnowRoute(id: "sr-5", code: "S5", name: "Seasonal residential", crewID: nil, propertyCount: 16, estimatedMinutes: 200, isDispatched: false, isBelowTrigger: true)
        ])
    }

    public var weather: Weather {
        Weather(temperatureC: 4, condition: "Cloudy", place: "Etobicoke", lowC: -1, outlook: "snow likely after 2 AM", snowWatch: true)
    }

    public var outbox: [OutboxItem] {
        [
            OutboxItem(id: "o-failed-photo", kind: .photoUpload, title: "1 photo didn't upload", detail: "Kingsway Plaza", createdAt: minutes(-130), state: .failed(attempts: 3), completedUnits: 0, totalUnits: 1, byteCount: 2_600_000),
            OutboxItem(id: "o-conflict", kind: .note, title: "Conflicting update", detail: "Access notes changed by Michael too", createdAt: minutes(-40), state: .needsAttention, conflictID: "sc-riverwood")
        ]
    }

    public var conflicts: [SyncConflict] {
        [
            SyncConflict(id: "sc-riverwood", propertyID: ID.riverwood, fieldName: "access notes", mine: ConflictVersion(text: "Gate code changed — ask board. Leaves bagged, not mulched. Park on Riverwood Cres.", editedAt: minutes(-46), editedBy: "iPhone"), office: ConflictVersion(text: "Gate code changed — ask board. Visitor parking only, not the fire lane.", editedAt: minutes(-40), editedBy: "Michael"))
        ]
    }

    public var analytics: [AnalyticsRange: AnalyticsSnapshot] {
        let crewsWeek = [
            AnalyticsSnapshot.CrewRow(id: ID.crewA, name: "Crew A", visits: 41, onTimeRate: 0.95),
            AnalyticsSnapshot.CrewRow(id: ID.crewB, name: "Crew B", visits: 36, onTimeRate: 0.84),
            AnalyticsSnapshot.CrewRow(id: ID.crewC, name: "Crew C", visits: 34, onTimeRate: 0.93)
        ]
        let labels = (0..<7).map { i -> String in
            let d = cal.date(byAdding: .day, value: i - 6, to: today)!
            return String(Fmt.weekdayShort(d).prefix(1))
        }
        return [
            .week: AnalyticsSnapshot(visitsCompleted: 142, visitsChange: 0.08, onTimeRate: 0.91, onTimeChange: 0, minutesVsEstimate: 2, minutesVsEstimateChange: 1, billed: 24860, billedChange: 0.12, dailyVisits: [31, 29, 33, 27, 8, 0, 14], dayLabels: labels, crews: crewsWeek),
            .month: AnalyticsSnapshot(visitsCompleted: 588, visitsChange: 0.05, onTimeRate: 0.90, onTimeChange: -0.01, minutesVsEstimate: 3, minutesVsEstimateChange: 0, billed: 98420, billedChange: 0.07, dailyVisits: [120, 131, 142, 139, 56], dayLabels: ["W1", "W2", "W3", "W4", "W5"], crews: crewsWeek.map { .init(id: $0.id, name: $0.name, visits: $0.visits * 4, onTimeRate: $0.onTimeRate - 0.01) }),
            .season: AnalyticsSnapshot(visitsCompleted: 4210, visitsChange: 0.11, onTimeRate: 0.89, onTimeChange: 0.02, minutesVsEstimate: 4, minutesVsEstimateChange: -1, billed: 712300, billedChange: 0.15, dailyVisits: [520, 610, 660, 702, 690, 640, 188], dayLabels: ["A", "M", "J", "J", "A", "S", "O"], crews: crewsWeek.map { .init(id: $0.id, name: $0.name, visits: $0.visits * 30, onTimeRate: $0.onTimeRate - 0.02) })
        ]
    }
}
