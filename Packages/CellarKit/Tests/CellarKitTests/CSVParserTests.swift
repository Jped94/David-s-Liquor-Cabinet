import Testing
@testable import CellarKit

@Suite struct CSVParserTests {
    @Test func parsesSimpleRows() {
        let rows = CSVParser.parse("a,b,c\n1,2,3\n")
        #expect(rows == [["a", "b", "c"], ["1", "2", "3"]])
    }

    @Test func handlesQuotedFieldsWithCommasAndEscapedQuotes() {
        let rows = CSVParser.parse(#""Ardbeg, Islay","He said ""peaty""",x"#)
        #expect(rows == [["Ardbeg, Islay", #"He said "peaty""#, "x"]])
    }

    @Test func handlesCRLFAndCRLineEndings() {
        #expect(CSVParser.parse("a,b\r\n1,2\r\n") == [["a", "b"], ["1", "2"]])
        #expect(CSVParser.parse("a,b\r1,2") == [["a", "b"], ["1", "2"]])
    }

    @Test func keepsLineBreaksInsideQuotes() {
        let rows = CSVParser.parse("note,x\n\"line one\r\nline two\",y\n")
        #expect(rows == [["note", "x"], ["line one\r\nline two", "y"]])
    }

    @Test func skipsBlankLinesButKeepsEmptyFields() {
        let rows = CSVParser.parse("a,b\n\n,\n\"\"\n")
        #expect(rows == [["a", "b"], ["", ""], [""]])
    }

    @Test func stripsByteOrderMark() {
        #expect(CSVParser.parse("\u{FEFF}iWine,Wine\n1,X") == [["iWine", "Wine"], ["1", "X"]])
    }

    @Test func handlesLastRowWithoutNewline() {
        #expect(CSVParser.parse("a\n\"b\"") == [["a"], ["b"]])
    }

    @Test func keepsUnescapedQuoteInsideQuotedFieldLeniently() {
        let rows = CSVParser.parse(#""Cask "Special" Edition",2"#)
        #expect(rows == [[#"Cask "Special" Edition"#, "2"]])
    }

    @Test func mapsRecordsByHeaderAndFillsMissingFields() {
        let (header, records) = CSVParser.parseRecords("iWine,Wine,Note\n42,Lagavulin 16\n")
        #expect(header == ["iWine", "Wine", "Note"])
        #expect(records == [["iWine": "42", "Wine": "Lagavulin 16", "Note": ""]])
    }
}
