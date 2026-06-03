//
//  Created by Alex.M on 27.06.2022.
//

import Foundation
import UIKit
import ExyteChat
import ExyteMediaPicker

final class MockChatData {

    // Alternative for avatars `https://ui-avatars.com/api/?name=Tim`
    let system = MockUser(uid: "0", name: "System")
    let tim = MockUser(
        uid: "1",
        name: "Tim",
        avatar: AssetExtractor.createLocalUrl(forImageNamed: "tim")!
    )
    let steve = MockUser(
        uid: "2",
        name: "Steve",
        avatar: AssetExtractor.createLocalUrl(forImageNamed: "steve")!
    )
    let bob = MockUser(
        uid: "3",
        name: "Bob",
        avatar: AssetExtractor.createLocalUrl(forImageNamed: "bob")!
    )

    func randomMessage(senders: [MockUser] = [], date: Date? = nil) -> MockMessage {
        let senders = senders.isEmpty ? [tim, steve, bob] : senders
        let sender = senders.random()!
        let date = date ?? Date()
        let images = randomImages()

        let shouldGenerateText = images.isEmpty ? true : .random()

        return MockMessage(
            uid: UUID().uuidString,
            sender: sender,
            createdAt: date,
            status: sender.isCurrentUser ? .read : nil,
            text: shouldGenerateText ? Lorem.sentence(nbWords: Int.random(in: 3...10), useMarkdown: true) : "",
            images: images,
            videos: [],
            reactions: [],
            recording: nil,
            replyMessage: nil
        )
    }

    func randomImages() -> [MockImage] {
        guard Int.random(min: 0, max: 10) == 0 else {
            return []
        }

        let count = Int.random(min: 1, max: 5)
        return (0...count).map { _ in
            randomMockImage()
        }
    }

    static let mockImageUrls: [String] = [
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_141024_5887f308-10e5-4d9d-9ec5-3f70efec04d9.png&w=1920&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134009_22a06f6b-e62c-4151-b23f-4d1e879213d5.png&w=1920&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134642_514483cf-494f-48d3-8afa-e5c09657f3f5.png&w=1920&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_200008_0b6093ac-2455-433e-a94b-d04398b4d37d.png&w=1920&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133537_cfe10641-be5a-49fa-a66d-f43e95197b52.png&w=1920&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_135124_fc776f6b-77ca-44cc-b7f0-e8970128ccd3.png&w=1920&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_140713_48e4c644-a2c8-46c4-84be-687a1782540a.png&w=1920&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133911_0d6d24dd-3e68-451a-9c4f-659164bb10de.png&w=1920&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_175012_a1d817dd-35eb-48d6-abd7-e2043f536696.png&w=1920&q=85",
        "https://higgsfield.ai/thumbnail/soul-v2.jpg",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_143902_8630b6a2-0813-4dc7-b737-00575e1df593.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260213_201650_322c2e1d-2643-4f06-8c06-dfda0246b527.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_122301_566a5b8f-230c-40fd-9d71-ca4cf65e6ffc.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260207_193655_711f3c26-8d2b-4e66-89e4-8357c0100b62.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_125528_74e01924-1a9b-4f3b-987f-6a568b0f2616.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260217_212611_922a5d2b-2a21-4b76-bae2-cf3d73bcbc12.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_123559_71e7ea08-10d6-487f-a815-042a83a33450.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260217_184432_7af6e3df-a5ad-4e8a-a3b4-c6d8637ce85c.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_184556_0e4b2d2d-e4b7-4d49-91e8-a67ed83fb932.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_155755_a1154075-36cb-4a51-b525-c75dc1fce731.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_140505_5ef95a64-65a4-45b1-8e80-fa6dfe073916.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260209_131824_f0307da0-93a0-41e0-8b37-9d34bb09b328.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_191141_25377443-e2fb-478b-8551-484c096d8e33.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_140621_0659e72b-b64a-44f5-ae26-8cc53ebbdb68.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_141245_0d705c3d-9177-4604-9b4a-d14f6639300c.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_133517_b2d87b9a-3395-4bfa-8abf-a301b5f8ac1f.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_154011_bf1ee9a2-53c6-451b-993a-6f1837a2bb37.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_135505_2aea9fe7-7896-4490-9805-2f42d7401701.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_141231_84aa5cab-7a78-4f0c-bb92-51fad4ef7458.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_191031_c9b98b75-71f3-4172-b50b-41bf080ecc25.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_150351_279f0573-cb77-40d3-be50-baf57c6d5d60.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_140509_c7a41b3f-6954-4f77-9a35-48d03e743412.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_140139_9c570336-93ca-476d-8625-33399c0f9978.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_134324_70350392-f345-40c0-94eb-86879e9d99cd.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_122727_f7159c87-80f4-432b-bb9c-8364f500eca1.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_133911_0d6d24dd-3e68-451a-9c4f-659164bb10de.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260214_152019_317ff455-7b44-4e73-93e0-bedfa9a992f6.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_181323_f9f3fdda-d51c-4476-bb18-9d438bf74ca7.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_140713_48e4c644-a2c8-46c4-84be-687a1782540a.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_161021_8e383ad8-bda5-4192-824f-c8bb783ffb40.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_135124_fc776f6b-77ca-44cc-b7f0-e8970128ccd3.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260217_175012_2482b23d-7762-4366-b718-3fde133ac10e.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_120631_b4bade9f-5e82-4e87-bc66-cea3e15d46de.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_140038_120113cf-5b10-46ba-ba39-5d48cd88b4e2.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_191747_d3bd5539-99fb-468d-ac7e-db49162a04fb.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260217_200008_0b6093ac-2455-433e-a94b-d04398b4d37d.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260217_144545_d716437f-cc84-4b68-9977-7ec3304eda7c.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_161308_2d5c71f5-472c-4780-9eeb-0ae483fb0d63.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_135458_3426788c-8993-4a17-a904-818aa42040d1.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_124914_3497c398-0398-44f7-a5b7-395d6c832886.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_134519_0e3628a6-250d-4998-a417-2e582d544820.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260216_203759_8e9b1d03-d9fd-48d9-bcc3-3554a84b2c2b.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_124022_074e36f3-f349-4a63-a436-ed0b0561a70b.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260214_212805_d231c17b-81f9-43b0-a06c-35e401f13486.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_190742_2ffd28b9-6a71-4772-8eeb-1a63d989f0d9.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_142730_c1d3b743-ccfc-4589-a004-127e59383b56.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_130053_6b20faa8-0007-468c-929c-449d0b1ce48d.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_164027_da6e0b74-2c5d-404c-9cf5-30ba1933cfcc.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_133627_11cff101-735d-4a7f-a3b0-f42925ecf056.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_142804_4e33d5ff-cfa6-48f3-810e-6b66254d727c.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_134642_514483cf-494f-48d3-8afa-e5c09657f3f5.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_130714_2430d3a3-b8b2-4c9e-894d-b29503ee12c0.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_134009_22a06f6b-e62c-4151-b23f-4d1e879213d5.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260217_175012_a1d817dd-35eb-48d6-abd7-e2043f536696.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_141135_4468ae61-47be-4396-834b-8bbc78054909.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_123341_5eeff76b-7e3b-4826-ae1c-ec7ac8b66643.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260214_185108_10d1d820-08e7-477d-a7bf-6e812b85b7d1.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_171001_e4013ff6-6e4a-411d-89b4-171c192dd5ef.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_182218_2cfc8314-b866-479e-a70e-b8f27b950e11.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_141024_5887f308-10e5-4d9d-9ec5-3f70efec04d9.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_134354_4595f2a8-ad3f-4c34-a675-dec445387460.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_154703_ab5763ab-98b2-43b6-9c4b-2059955e6f8f.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_133537_cfe10641-be5a-49fa-a66d-f43e95197b52.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260217_135500_2782de2f-ce1a-4109-a1a7-a345389784c1.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_140800_3330a6bc-1ef6-47ef-92a0-404a1ce2f200.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_142504_90e8d7ea-e3f0-44ee-b547-d982724d9b8f.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_142048_7e41cdec-560f-498d-85b7-6014159f915b.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_142019_2da23ac9-1bf0-4ba6-8b0c-11e45297c26e.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_163344_712a4fbe-979f-4f9c-a3c6-ff4257fefd3a.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_122400_6669d2ba-ef82-4168-99de-251f330dca5a.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260207_120803_5bb1f705-4a70-4f48-a437-62cec01d7426.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_134916_8cebbec0-c8dc-42f0-916c-2a48f2c61593.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260216_175717_ee0f68b1-180a-4bf5-8e40-20514fde2638.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_141002_0efc9f4a-125b-4af2-88aa-6c6422c5cd34.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_134617_669e020d-2374-48cd-b4ab-9f6935ff0fdd.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_135319_4c708c91-b27e-4393-bf7c-04f8c07a14fe.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_155039_a530fe30-f9d0-4d7a-a0dc-182a42816820.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_35h9Zqn0Bk5qurQOPUM7laOSfXO/hf_20260218_145720_b9c03b92-733e-46f3-aa3b-4347ca38f007.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260214_200319_4945a771-d388-4829-a7ac-957c12ff78c2.png",
        "https://d8j0ntlcm91z4.cloudfront.net/user_36Hwty94QweUxs82UEGsxmReIrf/hf_20260218_151350_320a2620-ef66-455d-806e-14da0c5462d1.png",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd2ol7oe51mr4n9.cloudfront.net%2Fanon_user_id%2F1ffde5a6-9413-45f2-8729-9792d1864ed6.png&w=1920&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260207_120803_5bb1f705-4a70-4f48-a437-62cec01d7426.png&w=1920&q=85",
        "https://static.higgsfield.ai/original-series/mork-promo/3x4%20Mork%20CLEAN%20(1)%201%20(1).png",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_141024_5887f308-10e5-4d9d-9ec5-3f70efec04d9.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_200008_0b6093ac-2455-433e-a94b-d04398b4d37d.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133911_0d6d24dd-3e68-451a-9c4f-659164bb10de.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134009_22a06f6b-e62c-4151-b23f-4d1e879213d5.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_175012_a1d817dd-35eb-48d6-abd7-e2043f536696.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_135124_fc776f6b-77ca-44cc-b7f0-e8970128ccd3.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133537_cfe10641-be5a-49fa-a66d-f43e95197b52.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_140713_48e4c644-a2c8-46c4-84be-687a1782540a.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134642_514483cf-494f-48d3-8afa-e5c09657f3f5.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd20rwh69pn04qo.cloudfront.net%2Fanon_user_id%2Fe77d75f0-5fc9-4c57-95bc-82b637fdb5f7.png&w=1920&q=85",
        "https://d2ol7oe51mr4n9.cloudfront.net/anon_user_id/1ffde5a6-9413-45f2-8729-9792d1864ed6.png",
        "https://d20rwh69pn04qo.cloudfront.net/anon_user_id/cc1c8368-0108-45ea-990c-9634973cfd92.webp",
        "https://d2ol7oe51mr4n9.cloudfront.net/anon_user_id/e42e6a9b-10e0-4c9f-b94c-1aef7b48b689.jpg",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260207_120803_5bb1f705-4a70-4f48-a437-62cec01d7426.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd2ol7oe51mr4n9.cloudfront.net%2Fanon_user_id%2F1ffde5a6-9413-45f2-8729-9792d1864ed6.png&w=1280&q=85",
        "https://d20rwh69pn04qo.cloudfront.net/anon_user_id/e77d75f0-5fc9-4c57-95bc-82b637fdb5f7.png",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd20rwh69pn04qo.cloudfront.net%2Fanon_user_id%2Fe77d75f0-5fc9-4c57-95bc-82b637fdb5f7.png&w=1280&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260216_175717_ee0f68b1-180a-4bf5-8e40-20514fde2638.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_125528_74e01924-1a9b-4f3b-987f-6a568b0f2616.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_181323_f9f3fdda-d51c-4476-bb18-9d438bf74ca7.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_140038_120113cf-5b10-46ba-ba39-5d48cd88b4e2.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_142019_2da23ac9-1bf0-4ba6-8b0c-11e45297c26e.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260214_200319_4945a771-d388-4829-a7ac-957c12ff78c2.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_164027_da6e0b74-2c5d-404c-9cf5-30ba1933cfcc.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_134519_0e3628a6-250d-4998-a417-2e582d544820.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_145720_b9c03b92-733e-46f3-aa3b-4347ca38f007.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_140139_9c570336-93ca-476d-8625-33399c0f9978.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260216_203759_8e9b1d03-d9fd-48d9-bcc3-3554a84b2c2b.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_124914_3497c398-0398-44f7-a5b7-395d6c832886.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_155039_a530fe30-f9d0-4d7a-a0dc-182a42816820.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_154703_ab5763ab-98b2-43b6-9c4b-2059955e6f8f.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_161021_8e383ad8-bda5-4192-824f-c8bb783ffb40.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134324_70350392-f345-40c0-94eb-86879e9d99cd.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_135505_2aea9fe7-7896-4490-9805-2f42d7401701.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_122301_566a5b8f-230c-40fd-9d71-ca4cf65e6ffc.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260213_201650_322c2e1d-2643-4f06-8c06-dfda0246b527.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_182218_2cfc8314-b866-479e-a70e-b8f27b950e11.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_142048_7e41cdec-560f-498d-85b7-6014159f915b.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_191031_c9b98b75-71f3-4172-b50b-41bf080ecc25.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_140505_5ef95a64-65a4-45b1-8e80-fa6dfe073916.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_184556_0e4b2d2d-e4b7-4d49-91e8-a67ed83fb932.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260217_212611_922a5d2b-2a21-4b76-bae2-cf3d73bcbc12.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133517_b2d87b9a-3395-4bfa-8abf-a301b5f8ac1f.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_151350_320a2620-ef66-455d-806e-14da0c5462d1.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_120631_b4bade9f-5e82-4e87-bc66-cea3e15d46de.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134009_22a06f6b-e62c-4151-b23f-4d1e879213d5.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_155755_a1154075-36cb-4a51-b525-c75dc1fce731.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_175012_2482b23d-7762-4366-b718-3fde133ac10e.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_122400_6669d2ba-ef82-4168-99de-251f330dca5a.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_135458_3426788c-8993-4a17-a904-818aa42040d1.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_175012_a1d817dd-35eb-48d6-abd7-e2043f536696.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_140800_3330a6bc-1ef6-47ef-92a0-404a1ce2f200.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_191141_25377443-e2fb-478b-8551-484c096d8e33.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260217_184432_7af6e3df-a5ad-4e8a-a3b4-c6d8637ce85c.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_154011_bf1ee9a2-53c6-451b-993a-6f1837a2bb37.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_190742_2ffd28b9-6a71-4772-8eeb-1a63d989f0d9.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_200008_0b6093ac-2455-433e-a94b-d04398b4d37d.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_134916_8cebbec0-c8dc-42f0-916c-2a48f2c61593.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260214_185108_10d1d820-08e7-477d-a7bf-6e812b85b7d1.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_141245_0d705c3d-9177-4604-9b4a-d14f6639300c.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133911_0d6d24dd-3e68-451a-9c4f-659164bb10de.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_141135_4468ae61-47be-4396-834b-8bbc78054909.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260209_131824_f0307da0-93a0-41e0-8b37-9d34bb09b328.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_140713_48e4c644-a2c8-46c4-84be-687a1782540a.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_122727_f7159c87-80f4-432b-bb9c-8364f500eca1.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_141231_84aa5cab-7a78-4f0c-bb92-51fad4ef7458.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_123341_5eeff76b-7e3b-4826-ae1c-ec7ac8b66643.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_141024_5887f308-10e5-4d9d-9ec5-3f70efec04d9.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_135124_fc776f6b-77ca-44cc-b7f0-e8970128ccd3.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_135500_2782de2f-ce1a-4109-a1a7-a345389784c1.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260214_152019_317ff455-7b44-4e73-93e0-bedfa9a992f6.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_171001_e4013ff6-6e4a-411d-89b4-171c192dd5ef.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260214_212805_d231c17b-81f9-43b0-a06c-35e401f13486.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_161308_2d5c71f5-472c-4780-9eeb-0ae483fb0d63.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133537_cfe10641-be5a-49fa-a66d-f43e95197b52.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134642_514483cf-494f-48d3-8afa-e5c09657f3f5.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_142730_c1d3b743-ccfc-4589-a004-127e59383b56.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_143902_8630b6a2-0813-4dc7-b737-00575e1df593.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_123559_71e7ea08-10d6-487f-a815-042a83a33450.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_140621_0659e72b-b64a-44f5-ae26-8cc53ebbdb68.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260207_120803_5bb1f705-4a70-4f48-a437-62cec01d7426.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_142804_4e33d5ff-cfa6-48f3-810e-6b66254d727c.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd2ol7oe51mr4n9.cloudfront.net%2Fanon_user_id%2F1ffde5a6-9413-45f2-8729-9792d1864ed6.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_124022_074e36f3-f349-4a63-a436-ed0b0561a70b.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260207_193655_711f3c26-8d2b-4e66-89e4-8357c0100b62.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_140509_c7a41b3f-6954-4f77-9a35-48d03e743412.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd20rwh69pn04qo.cloudfront.net%2Fanon_user_id%2Fe77d75f0-5fc9-4c57-95bc-82b637fdb5f7.png&w=640&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_141024_5887f308-10e5-4d9d-9ec5-3f70efec04d9.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_200008_0b6093ac-2455-433e-a94b-d04398b4d37d.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_135124_fc776f6b-77ca-44cc-b7f0-e8970128ccd3.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_140713_48e4c644-a2c8-46c4-84be-687a1782540a.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_175012_a1d817dd-35eb-48d6-abd7-e2043f536696.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134642_514483cf-494f-48d3-8afa-e5c09657f3f5.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133911_0d6d24dd-3e68-451a-9c4f-659164bb10de.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134009_22a06f6b-e62c-4151-b23f-4d1e879213d5.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133537_cfe10641-be5a-49fa-a66d-f43e95197b52.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd2ol7oe51mr4n9.cloudfront.net%2Fanon_user_id%2F1ffde5a6-9413-45f2-8729-9792d1864ed6.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260207_120803_5bb1f705-4a70-4f48-a437-62cec01d7426.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd20rwh69pn04qo.cloudfront.net%2Fanon_user_id%2Fe77d75f0-5fc9-4c57-95bc-82b637fdb5f7.png&w=384&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_141024_5887f308-10e5-4d9d-9ec5-3f70efec04d9.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_135124_fc776f6b-77ca-44cc-b7f0-e8970128ccd3.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_175012_a1d817dd-35eb-48d6-abd7-e2043f536696.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133911_0d6d24dd-3e68-451a-9c4f-659164bb10de.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134642_514483cf-494f-48d3-8afa-e5c09657f3f5.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134009_22a06f6b-e62c-4151-b23f-4d1e879213d5.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133537_cfe10641-be5a-49fa-a66d-f43e95197b52.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_140713_48e4c644-a2c8-46c4-84be-687a1782540a.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_200008_0b6093ac-2455-433e-a94b-d04398b4d37d.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd2ol7oe51mr4n9.cloudfront.net%2Fanon_user_id%2F1ffde5a6-9413-45f2-8729-9792d1864ed6.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260207_120803_5bb1f705-4a70-4f48-a437-62cec01d7426.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd20rwh69pn04qo.cloudfront.net%2Fanon_user_id%2Fe77d75f0-5fc9-4c57-95bc-82b637fdb5f7.png&w=160&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260218_141024_5887f308-10e5-4d9d-9ec5-3f70efec04d9.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_200008_0b6093ac-2455-433e-a94b-d04398b4d37d.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260217_175012_a1d817dd-35eb-48d6-abd7-e2043f536696.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_140713_48e4c644-a2c8-46c4-84be-687a1782540a.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134009_22a06f6b-e62c-4151-b23f-4d1e879213d5.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_134642_514483cf-494f-48d3-8afa-e5c09657f3f5.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133911_0d6d24dd-3e68-451a-9c4f-659164bb10de.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_135124_fc776f6b-77ca-44cc-b7f0-e8970128ccd3.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_36Hwty94QweUxs82UEGsxmReIrf%2Fhf_20260218_133537_cfe10641-be5a-49fa-a66d-f43e95197b52.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd2ol7oe51mr4n9.cloudfront.net%2Fanon_user_id%2Fe42e6a9b-10e0-4c9f-b94c-1aef7b48b689.jpg&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd8j0ntlcm91z4.cloudfront.net%2Fuser_35h9Zqn0Bk5qurQOPUM7laOSfXO%2Fhf_20260207_120803_5bb1f705-4a70-4f48-a437-62cec01d7426.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd2ol7oe51mr4n9.cloudfront.net%2Fanon_user_id%2F1ffde5a6-9413-45f2-8729-9792d1864ed6.png&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd20rwh69pn04qo.cloudfront.net%2Fanon_user_id%2Fcc1c8368-0108-45ea-990c-9634973cfd92.webp&w=64&q=85",
        "https://images.higgs.ai/?default=1&output=webp&url=https%3A%2F%2Fd20rwh69pn04qo.cloudfront.net%2Fanon_user_id%2Fe77d75f0-5fc9-4c57-95bc-82b637fdb5f7.png&w=64&q=85"
    ]

    func randomMockImage() -> MockImage {
        let url = MockChatData.mockImageUrls.randomElement() ?? "https://picsum.photos/300/300"
        return MockImage(
            id: UUID().uuidString,
            thumbnail: URL(string: url)!,
            full: URL(string: url)!
        )
    }
    
    func randomReaction(senders: [MockUser]) -> Reaction {
        let sampleEmojis: [String] = ["👍", "👎", "❤️", "🤣", "‼️", "❓", "🥳", "💪", "🔥", "💔", "😭"]
        return Reaction(
            user: senders.random()!.toChatUser(),
            createdAt: Date.now,
            type: .emoji(sampleEmojis.random()!),
            status: .sent
        )
    }
    
    func reactToMessage(_ msg: MockMessage, senders: [MockUser]) -> MockMessage {
        return MockMessage(
            uid: msg.uid,
            sender: msg.sender,
            createdAt: msg.createdAt,
            status: msg.status,
            text: msg.text,
            images: msg.images,
            videos: msg.videos,
            reactions: msg.reactions + [randomReaction(senders: senders)],
            recording: msg.recording,
            replyMessage: msg.replyMessage
        )
    }
}

class AssetExtractor {

    static func createLocalUrl(forImageNamed name: String) -> URL? {

        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = cacheDirectory.appendingPathComponent("\(name).pdf")

        guard fileManager.fileExists(atPath: url.path) else {
            guard
                let image = UIImage(named: name),
                let data = image.pngData()
            else { return nil }

            fileManager.createFile(atPath: url.path, contents: data, attributes: nil)
            return url
        }

        return url
    }
}
