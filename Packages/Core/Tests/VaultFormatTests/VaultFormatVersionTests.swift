import Testing
import VaultFormat

struct VaultFormatVersionTests {
    @Test func currentVersionIsOne() {
        #expect(VaultFormatVersion.current == 1)
    }

    @Test(arguments: [0, 1, 2])
    func canWriteMatchesSupportedRange(vaultVersion: Int) {
        #expect(VaultFormatVersion.canWrite(vaultVersion: vaultVersion) == (vaultVersion <= VaultFormatVersion.current))
    }

    @Test(arguments: Array(1...VaultFormatVersion.current))
    func supportedVersionsCanBeWritten(vaultVersion: Int) {
        #expect(VaultFormatVersion.canWrite(vaultVersion: vaultVersion))
    }

    @Test(arguments: [VaultFormatVersion.current + 1, 100])
    func newerVersionsCannotBeWritten(vaultVersion: Int) {
        #expect(!VaultFormatVersion.canWrite(vaultVersion: vaultVersion))
    }
}
