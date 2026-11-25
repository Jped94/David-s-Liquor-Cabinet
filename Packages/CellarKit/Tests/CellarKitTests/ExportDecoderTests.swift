import Foundation
import Testing
@testable import CellarKit

@Suite struct ExportDecoderTests {
    @Test func decodesWindows1252WhenNotValidUTF8() throws {
        // "Cachaça" with ç as the single windows-1252 byte 0xE7.
        var bytes = Array("Cacha".utf8)
        bytes.append(0xE7)
        bytes.append(Array("a".utf8)[0])
        let text = try ExportDecoder.decodeText(Data(bytes))
        #expect(text == "Cachaça")
    }

    @Test func honoursDeclaredCharset() throws {
        let utf8 = Data("Poitín".utf8)
        #expect(try ExportDecoder.decodeText(utf8, contentType: "text/csv; charset=UTF-8") == "Poitín")

        let cp1252 = Data([0x50, 0x6F, 0x69, 0x74, 0xED, 0x6E]) // "Poitín" in windows-1252
        #expect(try ExportDecoder.decodeText(cp1252, contentType: "text/csv; charset=windows-1252") == "Poitín")
    }

    @Test func parsesCharsetFromContentType() {
        #expect(ExportDecoder.charset(fromContentType: "text/csv; charset=Windows-1252") == "windows-1252")
        #expect(ExportDecoder.charset(fromContentType: #"text/csv;charset="utf-8""#) == "utf-8")
        #expect(ExportDecoder.charset(fromContentType: "text/csv") == nil)
    }

    @Test func detectsNotLoggedInPage() {
        let html = "<html><body>You are currently not logged into CellarTracker.</body></html>"
        #expect(throws: ExportError.notLoggedIn) {
            try ExportDecoder.parseBottles(html)
        }
    }

    @Test func detectsOtherHTML() {
        #expect(throws: ExportError.unexpectedHTML) {
            try ExportDecoder.parseBottles("\n  <!DOCTYPE html><html>Down for maintenance</html>")
        }
    }

    @Test func rejectsCSVWithoutRequiredColumns() {
        #expect(throws: ExportError.missingColumns(["iWine"])) {
            try ExportDecoder.parseBottles("Wine,Size\nX,750ml\n")
        }
    }

    @Test func mapsRowFields() throws {
        let csv = """
        "iInventory","iWine","Wine","Vintage","SubRegion","Pending","CNotes","CScore","Price"
        "7","4833686","Aberfeldy 25 Year Old, 46%","1001","Unknown","1","0","96","500.50"
        """
        let bottle = try #require(try ExportDecoder.parseBottles(csv).first)
        #expect(bottle.inventoryID == "7")
        #expect(bottle.wineID == "4833686")
        #expect(bottle.vintage == nil) // 1001 means no vintage
        #expect(bottle.subRegion == nil) // "Unknown" becomes nil
        #expect(bottle.isPending)
        #expect(bottle.communityNoteCount == nil)
        #expect(bottle.communityScore == 96)
        #expect(bottle.price == Decimal(string: "500.50"))
    }
}
