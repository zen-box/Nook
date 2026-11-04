import Foundation
import Testing
@testable import NookCore

struct MoneyTests {
    static let dollarInputs: [(String, Int64?)] = [
        ("1,280.50", 128_050),
        ("12.5", 1_250),
        ("-3", -300),
        ("+7", 700),
        (".5", 50),
        ("  42 ", 4_200),
        ("", nil),
        (".", nil),
        ("1.234", nil),
        ("1.2.3", nil),
        ("abc", nil),
        ("--5", nil),
        ("１２", nil),  // full-width digits
    ]

    @Test(arguments: MoneyTests.dollarInputs)
    func parsesDollars(input: String, expected: Int64?) {
        #expect(Money.parse(input, currencyCode: "USD")?.minorUnits == expected)
    }

    @Test func parsesOtherCurrenciesAndSeparators() {
        #expect(Money.parse("1,280", currencyCode: "JPY")?.minorUnits == 1_280)
        #expect(Money.parse("12.5", currencyCode: "JPY") == nil)
        #expect(Money.parse("1.234", currencyCode: "KWD")?.minorUnits == 1_234)
        #expect(Money.parse("1 280,50", currencyCode: "EUR", decimalSeparator: ",")?.minorUnits == 128_050)
        #expect(Money.parse("1.280,5", currencyCode: "EUR", decimalSeparator: ",")?.minorUnits == 128_050)
        #expect(Money.parse("12", currencyCode: "usd")?.currencyCode == "USD")
    }

    @Test func knowsMinorUnitDigits() {
        #expect(Money.minorUnitDigits(for: "USD") == 2)
        #expect(Money.minorUnitDigits(for: "CNY") == 2)
        #expect(Money.minorUnitDigits(for: "jpy") == 0)
        #expect(Money.minorUnitDigits(for: "KWD") == 3)
    }

    @Test func decimalValueUsesMinorUnits() {
        #expect(Fixtures.usd(128_050).decimalValue == Decimal(string: "1280.50"))
        #expect(Fixtures.usd(-5).decimalValue == Decimal(string: "-0.05"))
        #expect(Money(minorUnits: 1_280, currencyCode: "JPY").decimalValue == Decimal(1_280))
    }

    @Test func formatsWithTheNarrowSymbol() {
        #expect(Fixtures.usd(128_050).formatted(locale: Locale(identifier: "en_US")) == "$1,280.50")
    }

    @Test func addsAndSubtracts() {
        var sum = Fixtures.usd(100) + Fixtures.usd(250)
        #expect(sum == Fixtures.usd(350))
        sum += Fixtures.usd(50)
        #expect(sum.minorUnits == 400)
        #expect((Fixtures.usd(100) - Fixtures.usd(250)).minorUnits == -150)
        #expect(Money.zero("usd").isZero)
        #expect(Money.zero("usd").currencyCode == "USD")
    }

    @Test func codesAsMinorUnitsAndCurrency() throws {
        #expect(try Fixtures.jsonText(Fixtures.usd(128_050)) == #"{"amount_minor":128050,"currency":"USD"}"#)
        let decoded = try Fixtures.decode(Money.self, from: #"{"amount_minor":5,"currency":"jpy"}"#)
        #expect(decoded == Money(minorUnits: 5, currencyCode: "JPY"))
    }
}
