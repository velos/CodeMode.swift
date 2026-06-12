import Foundation
import Testing
@testable import CodeMode

#if canImport(CloudKit)
@preconcurrency import CloudKit
#endif
#if canImport(MapKit)
@preconcurrency import MapKit
#endif

@Test func cloudKitMappingValidatesDatabasePredicateAndFields() throws {
    #expect(try SystemCloudKitMapping.databaseName(arguments: [:]) == "private")
    #expect(try SystemCloudKitMapping.databaseName(arguments: ["database": .string("shared")]) == "shared")

    do {
        _ = try SystemCloudKitMapping.databaseName(arguments: ["database": .string("archive")])
        Issue.record("Expected invalid database to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    let predicate = try SystemCloudKitMapping.safePredicate(
        arguments: ["predicate": .object(["field": .string("status"), "equals": .string("open")])],
        capability: "cloudkit.records.query"
    )
    #expect(predicate?.field == "status")
    #expect(predicate?.equals == .string("open"))

    do {
        _ = try SystemCloudKitMapping.safePredicate(
            arguments: ["predicate": .string("TRUEPREDICATE")],
            capability: "cloudkit.records.query"
        )
        Issue.record("Expected raw predicate string to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    let fields = try SystemCloudKitMapping.recordFields(
        arguments: [
            "fields": .object([
                "title": .string("Review"),
                "rank": .number(1),
                "done": .bool(false),
                "tags": .array([.string("work"), .number(2)]),
            ]),
        ],
        capability: "cloudkit.record.save"
    )
    #expect(fields.keys.contains("title"))

    do {
        _ = try SystemCloudKitMapping.recordFields(
            arguments: ["fields": .object(["bad": .object(["nested": .bool(true)])])],
            capability: "cloudkit.record.save"
        )
        Issue.record("Expected nested record field object to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

#if canImport(CloudKit)
@Test func cloudKitMappingSerializesRecordOutput() throws {
    let record = CKRecord(recordType: "Task", recordID: CKRecord.ID(recordName: "task-1"))
    record["title"] = try SystemCloudKitMapping.recordValue(.string("Review"), field: "title")
    record["priority"] = try SystemCloudKitMapping.recordValue(.number(3), field: "priority")
    record["done"] = try SystemCloudKitMapping.recordValue(.bool(true), field: "done")
    record["tags"] = try SystemCloudKitMapping.recordValue(.array([.string("ios"), .string("agent")]), field: "tags")

    let object = try requireObject(SystemCloudKitMapping.recordJSON(record))
    #expect(object["recordName"]?.stringValue == "task-1")
    #expect(object["recordType"]?.stringValue == "Task")

    let fields = try #require(object["fields"]?.objectValue)
    #expect(fields["title"]?.stringValue == "Review")
    #expect(fields["priority"]?.intValue == 3)
    #expect(fields["done"]?.boolValue == true)
    #expect(fields["tags"]?.arrayValue?.compactMap(\.stringValue) == ["ios", "agent"])
}
#endif

@Test func mapsMappingValidatesCoordinatesTransportAndQueryURLs() throws {
    let coordinate = try SystemMapsMapping.coordinate(
        arguments: ["latitude": .number(37.3318), "longitude": .number(-122.0312)],
        name: "origin",
        capability: "maps.route.estimate"
    )
    #expect(coordinate.latitude == 37.3318)
    #expect(coordinate.longitude == -122.0312)

    do {
        _ = try SystemMapsMapping.coordinate(arguments: ["latitude": .number(37.3318)], name: "origin", capability: "maps.route.estimate")
        Issue.record("Expected missing longitude to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    #expect(try SystemMapsMapping.transportTypeName(arguments: [:], defaultValue: "automobile") == "automobile")
    #expect(try SystemMapsMapping.transportTypeName(arguments: ["transportType": .string("transit")]) == "transit")

    do {
        _ = try SystemMapsMapping.transportTypeName(arguments: ["transportType": .string("hoverboard")])
        Issue.record("Expected invalid transportType to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    let url = try SystemMapsMapping.appleMapsQueryURL(query: "Apple Park")
    #expect(url.absoluteString.contains("maps.apple.com"))
    #expect(url.absoluteString.contains("Apple%20Park"))
}

#if canImport(MapKit)
@Test func mapsMappingBuildsMapKitRegionAndLaunchOptions() throws {
    let radiusRegion = try #require(SystemMapsMapping.mapKitRegion([
        "latitude": .number(37.3318),
        "longitude": .number(-122.0312),
        "radiusMeters": .number(500),
    ]))
    #expect(radiusRegion.center.latitude == 37.3318)
    #expect(radiusRegion.center.longitude == -122.0312)

    let spanRegion = try #require(SystemMapsMapping.mapKitRegion([
        "center": .object(["latitude": .number(37.3318), "longitude": .number(-122.0312)]),
        "latitudeDelta": .number(0.2),
        "longitudeDelta": .number(0.3),
    ]))
    #expect(spanRegion.span.latitudeDelta == 0.2)
    #expect(spanRegion.span.longitudeDelta == 0.3)

    let rawLaunchOptions = try SystemMapsMapping.mapsLaunchOptions(["transportType": .string("walking")])
    let launchOptions = try #require(rawLaunchOptions)
    #expect(launchOptions[MKLaunchOptionsDirectionsModeKey] as? String == MKLaunchOptionsDirectionsModeWalking)

    let item = SystemMapsMapping.mapItem(coordinate: [
        "latitude": .number(37.3318),
        "longitude": .number(-122.0312),
        "name": .string("Apple Park"),
    ])
    #expect(item.name == "Apple Park")
    #expect(item.placemark.coordinate.latitude == 37.3318)
}
#endif
