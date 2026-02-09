import Blockchain
import Codec
import Foundation
@testable import Node
import Testing
import Utils

final class BlockAnnouncementDecoderTests {
    @Test
    func decodeInvalidEpoch() throws {
        let hexString = """
        ed0100007d810035df13056b2e28c4c331a7a53094e97a2b8bceff223ecd34b6cffd2d9ab69998d70\
        574f759fc057a99604de71d302cb16d365985a180bd8f3387d2d736189d15af832dfe4f67744008b6\
        2c334b569fcbb4c261e0f065655697306ca252ff000000010000000000000000000000000000000000\
        0000000000000000000000000000000000000000000000000000000000000000000000000000000000\
        5e465beb01dbafe160ce8216047f2155dd0569f058afd52dcea601025a8d161d2c5da3a09d66a5d43\
        e7d523e6108736db99d2c2f08fbdcb72a4e8e5aced3482a8552b36000b454fdf6b5418e22ef5d6609\
        e8fc6b816822f02727e085c514d560000000004fbacc2baea15e2e69185623e37a51ee9372ebd80dd\
        405a34d24a0a40f79e1d92d49a247d13acca8ccaf7cb6d3eb9ef10b3ef29a93e01e9ddce0a4266c4a\
        2c0e96a3b8c26c8ac6c9063ed7dcdb18479736c7c7be7fbfd006b4cb4b44ffa948154fbacc2baea15\
        e2e69185623e37a51ee9372ebd80dd405a34d24a0a40f79e1d993ccc91f31f5d8657ef98d203ddcc7\
        38482fe2caaa41f51d983239ac0dbbba04ca820ff3eb8d2ab3b9e1421f7955d876776b0c293f2e31e\
        aa2da18c3b580f5067d810035df13056b2e28c4c331a7a53094e97a2b8bceff223ecd34b6cffd2d9a
        """
        let hex = hexString.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let data = try #require(Data(fromHexString: hex))
        let config = ProtocolConfigRef.minimal
        #expect(throws: DecodingError.self) {
            _ = try JamDecoder.decode(BlockAnnouncement.self, from: data, withConfig: config)
        }
    }

    @Test
    func decodeNotEnoughDataToDecode() throws {
        let hexString = """
        371134fcf189799fea21d2b9a50bd8352c7814a120617700e1f984af1cb3698fb1aed1999185b3800\
        51235aa97f33306a9682e486b12c6016e6df19ea71f1ff6189d15af832dfe4f67744008b62c334b56\
        9fcbb4c261e0f065655697306ca252ab00000001000000000000000000000000000000000000000000\
        0000000000000000000000000000000000000000000000000000000000000000000000000000000000\
        5e465beb01dbafe160ce8216047f2155dd0569f058afd52dcea601025a8d161d2c5da3a09d66a5d43\
        e7d523e6108736db99d2c2f08fbdcb72a4e8e5aced3482a8552b36000b454fdf6b5418e22ef5d6609\
        e8fc6b816822f02727e085c514d5605d069d7591ea55d9cc7adb9e8eaff66a1688d075c69fa94815e\
        f0fe9a56025699a565d486952598747cb9b3b78bb97694100a1cbf8d7af4eb2ea740b844b41d19a99\
        09db141ee10d89f9bff13d651831cc91098bdf30c917ce89d1b8416af719000000004fbacc2baea15\
        e2e69185623e37a51ee9372ebd80dd405a34d24a0a40f79e1d92d49a247d13acca8ccaf7cb6d3eb9e\
        f10b3ef29a93e01e9ddce0a4266c4a2c0e96a3b8c26c8ac6c9063ed7dcdb18479736c7c7be7fbfd00\
        6b4cb4b44ffa948154fbacc2baea15e2e69185623e37a51ee9372ebd80dd405a34d24a0a40f79e1d9\
        575f1115fe3f8a903ac06a3578eeb154ef3f75d2d18fcabfafa4f14530a27f050258515937b7f7bfe\
        f6bf7aa67adf39b59057bbbe0433c9e8a057917c836f814371134fcf189799fea21d2b9a50bd8352c\
        7814a120617700e1f984af1cb3698f00000000
        """
        let hex = hexString.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let data = try #require(Data(fromHexString: hex))
        let config = ProtocolConfigRef.minimal
        #expect(throws: DecodingError.self) {
            _ = try JamDecoder.decode(BlockAnnouncement.self, from: data, withConfig: config)
        }
    }
}
