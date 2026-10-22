import Foundation
import Testing

@testable import HikkiAI

struct AIPicturesTests {
    private let answer = """
        Three watercolors, one per day.

        ```hikki-pictures
        {"pictures":[
          {"prompt":"Torii gates at Fushimi Inari, early morning, watercolor","shape":"wide"},
          {"prompt":"  Arashiyama bamboo grove  ","shape":"tall","detailed":true},
          {"prompt":"Yasaka Pagoda at dusk","shape":"hexagon","from":"m1-0"},
          {"prompt":"","shape":"square"},
          {"prompt":"The same pagoda at night","from":"nope"},
          {"prompt":"A fifth one past the limit"},
          {"prompt":"A sixth"}
        ]}
        ```
        """

    @Test func theChatShowsTheAnswerWithoutItsPictures() {
        #expect(AIPageEdits.prose(answer) == "Three watercolors, one per day.")
        #expect(AIPictures.hasPictures(answer))
        #expect(AIPageEdits.prose("Here they come.\n\n```hikki-pic") == "Here they come.")
        #expect(!AIPictures.hasPictures("No pictures."))
    }

    @Test func onlyPicturesThatFitAreKeptUpToTheLimit() {
        let pictures = AIPictures.pictures(in: answer, known: ["m1-0"])
        #expect(pictures.count == AIPictures.maxPerAnswer)
        #expect(pictures[0] == PictureSpec(prompt: "Torii gates at Fushimi Inari, early morning, watercolor", shape: .wide))
        #expect(pictures[1] == PictureSpec(prompt: "Arashiyama bamboo grove", shape: .tall, detailed: true))
        // An unknown shape is wide; a known earlier picture may be changed, an unknown one is a new picture.
        #expect(pictures[2] == PictureSpec(prompt: "Yasaka Pagoda at dusk", shape: .wide, from: "m1-0"))
        #expect(pictures[3] == PictureSpec(prompt: "The same pagoda at night"))
        #expect(PictureShape.tall.aspect < 1 && PictureShape.wide.aspect > 1)
        #expect(AIPictures.pictures(in: "```hikki-pictures\nnot json\n```").isEmpty)
        #expect(AIPictures.pictures(in: "Just words.").isEmpty)
    }

    @Test func aChangeRunsOnTheDetailedModel() {
        #expect(PictureRequest(prompt: "a", shape: .wide, detailed: false).model == AIPictures.fastModel)
        #expect(PictureRequest(prompt: "a", shape: .wide, detailed: true).model == AIPictures.detailedModel)
        let change = PictureRequest(prompt: "a", shape: .wide, detailed: false, source: (Data([1]), "image/png"))
        #expect(change.model == AIPictures.detailedModel)
    }

    @Test func aNewPictureIsAskedForAsJSON() throws {
        let client = try OpenAIPictureClient.make(key: "sk-test", base: AIEndpoint.defaultBase(.openAI))
        let request = try client.urlRequest(PictureRequest(prompt: "A pagoda", shape: .tall, detailed: false))
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/generations")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == AIPictures.fastModel)
        #expect(body["size"] as? String == "1024x1536")
        #expect(body["prompt"] as? String == "A pagoda")
        #expect(body["stream"] as? Bool == true)
        #expect(body["partial_images"] as? Int == 2)
        #expect(body["n"] as? Int == 1)
    }

    @Test func aChangeSendsThePictureAsAFormPart() throws {
        let client = try OpenAIPictureClient.make(key: "sk-test", base: AIEndpoint.defaultBase(.openAI))
        let picture = Data("PNGDATA".utf8)
        let request = try client.urlRequest(
            PictureRequest(prompt: "At night", shape: .square, detailed: false, source: (picture, "image/png")))
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/edits")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("name=\"image[]\"; filename=\"picture.png\""))
        #expect(body.contains("PNGDATA"))
        #expect(body.contains("name=\"model\"\r\n\r\n\(AIPictures.detailedModel)"))
        #expect(body.contains("name=\"size\"\r\n\r\n1024x1024"))
    }

    @Test func aKeyGoesOnlyWhereItMay() {
        #expect(throws: AIError.missingKey(.openAI)) { try OpenAIPictureClient.make(key: "", base: AIEndpoint.defaultBase(.openAI)) }
        #expect(throws: AIError.badBaseURL(.openAI)) {
            try OpenAIPictureClient.make(key: "sk", base: URL(string: "http://example.com/v1")!)
        }
    }

    @Test func streamEventsBecomePictureEvents() throws {
        let b64 = Data([1, 2, 3]).base64EncodedString()
        #expect(
            try OpenAIPictureClient.event(["type": "image_generation.partial_image", "b64_json": b64])
                == .partial(Data([1, 2, 3])))
        #expect(
            try OpenAIPictureClient.event(["type": "image_edit.completed", "b64_json": b64, "output_format": "png"])
                == .done(Data([1, 2, 3]), fileExtension: "png"))
        #expect(
            try OpenAIPictureClient.event(["type": "image_generation.completed", "b64_json": b64])
                == .done(Data([1, 2, 3]), fileExtension: "jpg"))
        #expect(try OpenAIPictureClient.event(["type": "keepalive"]) == nil)
        #expect(throws: AIError.refused) {
            try OpenAIPictureClient.event(["type": "error", "error": ["code": "moderation_blocked", "message": "no"]])
        }
        #expect(throws: AIError.rateLimited) {
            try OpenAIPictureClient.event(["type": "error", "error": ["code": "rate_limit_exceeded", "message": ""]])
        }
    }

    @Test func aWholeAnswerIsThePicture() throws {
        let body = Data(#"{"data":[{"b64_json":"\#(Data([9]).base64EncodedString())"}],"output_format":"webp"}"#.utf8)
        #expect(try OpenAIPictureClient.whole(body) == .done(Data([9]), fileExtension: "webp"))
        #expect(throws: AIError.invalidResponse) { try OpenAIPictureClient.whole(Data("{}".utf8)) }
    }

    @Test func aDeclinedPictureIsRefused() {
        let body = Data(#"{"error":{"code":"moderation_blocked","type":"image_generation_user_error","message":"Blocked"}}"#.utf8)
        #expect(HTTPErrors.map(status: 400, body: body) == .refused)
    }

    @Test func theChatOffersPicturesOnlyWhenItCanMakeThem() {
        let model = AIModelCatalog.gptSol
        let plain = AIPrompts.chat([.user("Hi")], model: model, webSearch: false)
        #expect(!plain.instructions.contains("hikki-pictures"))
        let pictures = AIPrompts.chat(
            [.user("Draw it")], model: model, webSearch: false, pictures: true, pictureRequest: (.square, true))
        #expect(pictures.instructions.contains("hikki-pictures"))
        #expect(pictures.messages.last?.text.contains("make them square, detailed") == true)
    }
}
