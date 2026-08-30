<a href="https://exyte.com/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/exyte/media/master/common/header-dark.png"><img src="https://raw.githubusercontent.com/exyte/media/master/common/header-light.png"></picture></a>

<a href="https://exyte.com/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/exyte/media/master/common/our-site-dark.png" width="80" height="16"><img src="https://raw.githubusercontent.com/exyte/media/master/common/our-site-light.png" width="80" height="16"></picture></a>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<a href="https://twitter.com/exyteHQ"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/exyte/media/master/common/twitter-dark.png" width="74" height="16"><img src="https://raw.githubusercontent.com/exyte/media/master/common/twitter-light.png" width="74" height="16">
</picture></a> <a href="https://exyte.com/contacts"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/exyte/media/master/common/get-in-touch-dark.png" width="128" height="24" align="right"><img src="https://raw.githubusercontent.com/exyte/media/master/common/get-in-touch-light.png" width="128" height="24" align="right"></picture></a>

<table>
    <thead>
        <tr>
            <th>Chat</th>
            <th>Media</th>
            <th>Audio Messages</th>
            <th>Extra</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td>
                <img src="https://github.com/exyte/Chat/assets/1358172/baf0167f-b3e0-4df2-bd3b-b6b1c4ee385d" />
            </td>
            <td>
                <img src="https://github.com/exyte/Chat/assets/1358172/d62876ef-4475-4f07-933a-9d9366b02e28" />
            </td>
            <td>
                <img src="https://github.com/exyte/Chat/assets/1358172/ebd2040d-1cf0-4066-9391-592af1426571" />
            </td>
            <td>
                <img src="https://github.com/exyte/Chat/assets/1358172/053bcd73-0db7-44da-abd6-0a57f0f88a4b" />
            </td>
        </tr>
    </tbody>
</table>

<p><h1>Chat</h1></p>
<p><h4>A SwiftUI Chat UI framework with fully customizable message cells and a built-in media picker</h4></p>

![](https://img.shields.io/github/v/tag/exyte/Chat?label=Version)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fexyte%2FChat%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/exyte/Chat)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fexyte%2FChat%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/exyte/Chat)
[![SPM](https://img.shields.io/badge/SPM-Compatible-brightgreen.svg)](https://swiftpackageindex.com/exyte/Chat)
[![Cocoapods](https://img.shields.io/badge/Cocoapods-Deprecated%20after%202.4.2-yellow.svg)](https://cocoapods.org/pods/ExyteChat)
[![License: MIT](https://img.shields.io/badge/License-MIT-black.svg)](https://opensource.org/licenses/MIT)

# Features
- Displays your messages with pagination and allows you to create and "send" new messages (sending means calling a closure since user will be the one providing actual API calls)
- Allows you to pass a custom view builder for messages and input views
- Has a built-in photo and video library/camera picker for multiple media asset selection
- Sticker keyboard that integrates with Giphy
- Can display a fullscreen menu on long press a message cell (automatically shows scroll for big messages)
- Supports "reply to message" via message menu or through a closure. Remove and edit are **coming soon**
- This library allows to send the following content in messages in any combination:
    - Arbitrarily styled text with `AttributedString` or markdown
    - Photo/video
    - Audio recording
    - Link with preview
    - Gif/Sticker
    - Custom dictionary of any Sendable

    **Coming soon:**
    - User's location
    - Documents

## Migration to version 3

- `enableLoadMore(pageSize...)` renamed `enableLoadMore(offset...)` and its trailing closure doesn't have any arguments
- `linkPreviewsDisabled` refactored `linkPreviewsEnabled`
- `shouldShowLinkPreview` renamed `shouldShowPreviewForLink`
- `messageUseMarkdown` and `messageUseStyler` removed. now messages use markdown and underline links by default. if you'd like to use your own attributes, use `Message`'s init taking AttributedString. storing `AttributedString` directly instead of storing a string and applying attributes on-the-fly is more efficient.
- The closure arguments of `messageBuilder` and `inputViewBuilder` now each consist of a single struct (they are different structs). See [`ChatBuilderParameters.swift`](./Sources/ExyteChat/Views/ChatBuilderParameters.swift)

# Usage

Create a chat view like this:
```swift
@State var messages: [Message] = []

var body: some View {
    ChatView(messages: messages) { draft in
        yourViewModel.send(draft: draft)
    }
}
```
where:  
   `messages` - list of messages to display  
   `didSendMessage` - a closure which is called when the user presses the send button  

`Message` is a type that `Chat` uses for the internal implementation. In the code above it expects the user to provide a list of `Message` structs, and it returns a `DraftMessage` in the `didSendMessage` closure. You can map it both ways to your own `Message` model that your API expects or use as is.

`Message` stores the text in an `AttributedString`. You can pass your own `AttributedString` or a simple `String`, in which case `Message`'s init will apply default attributes: markdown and links underlines.

## Available chat types
Chat type - determines the order of messages and direction of new message animation. Available options:
- `conversation` - the latest message is at the bottom, new messages appear from the bottom  
- `comments` - the latest message is at the top, new messages appear from the top  

Reply mode - determines how replying to message looks. Available options:
- `quote` - when replying to message A, new message will appear as the newest message, quoting message A in its body  
- `answer` - when replying to message A, new message with appear directly below message A as a separate cell without duplicating message A in its body  

To specify any of these pass them through `init`:
```swift
ChatView(messages: viewModel.messages, chatType: .comments, replyMode: .answer) { draft in
    yourViewModel.send(draft: draft)
}
```

## Custom UI
You may customize message cells like this: 
```swift
ChatView(messages: viewModel.messages) { draft in
    viewModel.send(draft: draft)
} messageBuilder: { params in
    let message = params.message
    VStack {
        Text(message.attributedText)
        if !message.attachments.isEmpty {
            ForEach(message.attachments, id: \.id) { at in
                AsyncImage(url: at.thumbnail)
            }
        }
    }
}
```

To customize only some messages while keeping the default style for others, use `messageBuilder` and return your custom view for the messages you want to style, and `params.defaultMessageView()` for the rest. This way you can mix custom message cards with ExyteChat's built-in styling in the same chat.

```swift
ChatView(messages: viewModel.messages) { draft in
    viewModel.send(draft: draft)
} messageBuilder: { params in
    if needsCustomUI(params.message) {
        MyCustomMessageView(message: params.message)
    } else {
        params.defaultMessageView()
    }
}
```

Here `params` is a [`MessageBuilderParameters`](./Sources/ExyteChat/Views/ChatBuilderParameters.swift) struct, it has the following parameters:  
- `message` - the message containing user info, attachments, etc.   
- `positionInUserGroup` - the position of the message in its continuous collection of messages from the same user    
- `positionInMessagesSection` position of message in the section of messages from that day
- `positionInCommentsGroup` - position of message in its continuous group of comments (only works for .answer ReplyMode, nil for .quote mode)  
- `showContextMenuClosure` - closure to show message context menu   
- `messageActionClosure ` - closure to pass user interaction, .reply for example   
- `showAttachmentClosure` - you can pass an attachment to this closure to use ChatView's fullscreen media viewer    

You may customize the input view (a text field with buttons at the bottom) like this: 
```swift
ChatView(messages: viewModel.messages) { draft in
    viewModel.send(draft: draft)
} inputViewBuilder: { params in
    let action = params.inputViewActionClosure
    Group {
        switch params.inputViewStyle {
        case .message: // input view on chat screen
            VStack {
                HStack {
                    Button("Send") { action(.send) }
                    Button("Attach") { action(.photo) }
                }
                TextField("Write your message", text: params.text)
            }
        case .signature: // input view on photo selection screen
            VStack {
                HStack {
                    Button("Send") { action(.send) }
                }
                TextField("Compose a signature for photo", text: params.text)
                    .background(Color.green)
            }
        }
    }
}

```
Here `params` is an [`InputViewBuilderParameters`](./Sources/ExyteChat/Views/ChatBuilderParameters.swift) struct, it has the following parameters:   
- `textBinding` to bind your own TextField   
- `attachments` is a struct containing photos, videos, recordings and a message you are replying to     
- `inputViewState` - the state of the input view that is controlled by the library automatically if possible or through your calls of `inputViewActionClosure`
- `inputViewStyle` - `.message` or `.signature` (the chat screen or the photo selection screen)   
- `inputViewActionClosure` for calling on taps on your custom buttons. For example, call `inputViewActionClosure(.send)` if you want to send your message with your own button, then the library will reset the text and attachments and call the `didSendMessage` sending closure   
- `dismissKeyboardClosure` - call this to dismiss keyboard    

## Custom message menu
Long tap on a message will display a menu for this message (can be turned off, see Modifiers). To define custom message menu actions declare an enum conforming to `MessageMenuAction`. Then the library will show your custom menu options on long tap on message instead of default ones, if you pass your enum's name to it (see code sample). Once the action is selected special callback will be called. Here is a simple example:
```swift
enum Action: MessageMenuAction {
    case reply, edit

    func title() -> String {
        switch self {
        case .reply:
            "Reply"
        case .edit:
            "Edit"
        }
    }
    
    func icon() -> Image {
        switch self {
        case .reply:
            Image(systemName: "arrowshape.turn.up.left")
        case .edit:
            Image(systemName: "square.and.pencil")
        }
    }
    
    // Optional
    // Implement this method to conditionally include menu actions on a per message basis
    // The default behavior is to include all menu action items
    static func menuItems(for message: ExyteChat.Message) -> [Action] {
        if message.user.isCurrentUser  {
            return [.edit]
        } else {
            return [.reply]
        }
    }
}

ChatView(messages: viewModel.messages) { draft in
    viewModel.send(draft: draft)
} messageMenuAction: { (action: Action, defaultActionClosure, message) in // <-- here: specify the name of your `MessageMenuAction` enum
    switch action {
    case .reply:
        defaultActionClosure(message, .reply)
    case .edit:
        defaultActionClosure(message, .edit { editedText in
            // update this message's text on your BE
            print(editedText)
        })
    }
}
```
`messageMenuAction`'s parameters:  
- `selectedMenuAction` - action selected by the user from the menu. NOTE: when declaring this variable, specify its type (your custom descendant of MessageMenuAction) explicitly    
- `defaultActionClosure` - a closure taking a case of default implementation of MessageMenuAction which provides simple actions handlers; you call this closure passing the selected message and choosing one of the default actions (.reply, .edit) if you need them; or you can write a custom implementation for all your actions, in that case just ignore this closure
- `message` - message for which the menu is displayed
    
When implementing your own `MessageMenuActionClosure`, write a switch statement passing through all the cases of your `MessageMenuAction`, inside each case write your own action handler, or call the default one. NOTE: not all default actions work out of the box - e.g. for `.edit` you'll still need to provide a closure to save the edited text on your BE. Please see CommentsExampleView in ChatExample project for MessageMenuActionClosure usage example.

## Small view builders:
These use `AnyView`, so please try to keep them easy enough
- `mainHeaderBuilder` - a header for the whole chat, which will scroll together with all the messages and headers  
- `headerBuilder` - date section header builder   
- `betweenListAndInputViewBuilder` - content to display in between the chat list view and the input view   

## Modifiers   
`isListAboveInputView` - messages table above the input field view or not    
`showScrollToBottomButton` - little arrow button appearing when offset != 0     
`showNetworkConnectionProblem` - display network error on/off    
`showDateHeaders` - show section headers with dates between days, default is `true`     
`isScrollEnabled` - forbid scrolling for messages' `UITableView`      
`keyboardDismissMode` - set keyboard dismiss mode for the chat list (.interactive, .onDrag, or .none), default is .none    
`autoFocusTextInputOnChatOpen` - automatically focus the inputTextView when the chat view is opened, default is `false`
`showMessageMenuOnLongPress` - turn menu on long tap on/off    
`messageMenuAnimationDuration` - control how fast/snappy the message menu animations feel    
`contentInsets` - set additional content insets for the messages list   
`onContentOffsetChange` - get table's content offset updates  
`scrollTo` - scroll to messageID, certain pixels offset, top or bottom
`onWillDisplayCell` - UITableView's will display cell delegate calls this closure     
`enableLoadMore(offset: Int = 0, _ handler: @escaping ()->())` - when user scrolls up to `offset`-th message from the end, call the handler   function, so user can load more messages    
`localization` - can be localized in the Localizable.strings files    

### Update transactions
`updateTransaction` - awaitable updates helper similar in usage to `tableView.performBatchUpdates`
```swift
await updateTransaction(animationMode: .natural) {
    self.messages.append(nextMessage)
    self.currentTableContentOffset = offset
}
``` 
available modes are:
- `none` - no animations
- `natural` - standard UITableView's animations
- `keepStable` - no animations + if you insert rows to the "front" of the table - it keeps the current scroll position (normally it would jump because contentSize and contentOffset changed)

### Reactions    
`messageReactionDelegate` - provide a custom reaction delegate for handling and configuring message reactions    
`onMessageReaction` - configure reactions using closures (didReactTo, canReactTo, available reactions, emoji search, overview, etc.)  

## Custom swipe actions

```swift
// Example: Adding Swipe Actions to your ChatView
ChatView(messages: viewModel.messages) { draft in
    viewModel.send(draft: draft)
} 
.swipeActions(edge: .leading, performsFirstActionWithFullSwipe: false, items: [
    // SwipeActions are similar to Buttons, they accept an Action and a ViewBuilder
    SwipeAction(action: onDelete, activeFor: { $0.user.isCurrentUser }, background: .red) {
        swipeActionButtonStandard(title: "Delete", image: "xmark.bin")
    },
    // Set the background color of a SwipeAction in the initializer,
    // instead of trying to apply a background color in your ViewBuilder
    SwipeAction(action: onReply, background: .blue) {
        swipeActionButtonStandard(title: "Reply", image: "arrowshape.turn.up.left")
    },
    // SwipeActions can also be selectively shown based on the message,
    // here we only show the Edit action when the message is from the current sender
    SwipeAction(action: onEdit, activeFor: { $0.user.isCurrentUser }, background: .gray) {
        swipeActionButtonStandard(title: "Edit", image: "bubble.and.pencil")
    }
])
```
`swipeActions`'s parameters:  
- `edge` - either the leading or trailing edge of the Message
- `performsFirstActionWithFullSwipe` - if true, a full swipe will trigger the first `SwipeAction` provided in the `items` list
- `items` - list of `SwipeAction`s to include  

### makes sense only for built-in message view    
`showMessageTimeView` - show timestamp in a corner of the message    
`showUsername` - show username on top of message
`messageLinkPreviewLimit` - limit the maximum number of link previews per message    
`linkPreviewsEnabled` - enable or disable message link previews globally    
`shouldShowPreviewForLink` - provide custom logic to decide whether a specific URL should show a preview    
`setMessageFont` - pass custom font to use for messages      

`showAvatar` - show user avatars    
`avatarSize` - the default avatar is a circle, you can specify its diameter here    
`tapAvatarClosure` - closure to call on avatar tap    
`avatarBuilder` - custom avatar view builder. NOTE: this view is not autosizing, `avatarSize` will still be applied, since it needs to be fixed and same for all user avatars   

### makes sense only for built-in input view    
`inputViewText` - binding to current text in the default input text field    
`setAvailableInputs` - construct an array of these:    
    - `.text`    
    - `.media`    
    - `.audio`    
    - `.giphy`    
`setAvailableAttachmentInputs` - choose which sources the built-in media menu shows: `.photoLibrary`, `.camera`, and/or `.document`; all three remain enabled by default
`setEnabledInputs` - keep configured input controls visible while temporarily disabling actions that are unavailable because of capability, consent, or configuration state
`inputViewActionsEnabled` - temporarily disable send and attachment actions without disabling or hiding the text field
`setAllowsMixedMediaAndGiphy` - keep the source-compatible default or make local media and GIPHY mutually exclusive when the app contract uses one body kind per message
`didSubmitMessage` initializer - return `.accepted` to clear the built-in draft or `.keepDraft` to retain editable text and photo media after a synchronous rejection; immediate GIPHY selections are cleared so they cannot remain invisibly attached; the existing `didSendMessage` initializer keeps its original clear-after-send behavior
`setRecorderSettings` - customize audio recorder settings    
`assetsPickerLimit` - set a limit for MediaPicker built into the library    
`setMediaPickerSelectionParameters` - a struct holding MediaPicker selection parameters (selection limit, media type, selection style, etc.)    
`setMediaPickerParameters` - configure low-level MediaPicker parameters    
`orientationHandler` - handle screen rotation during media picking    

### Customize default colors and images
You can use `chatTheme` to customize colors and images of default UI. You can pass all/some colors and images:

```swift
.chatTheme(
    ChatTheme(
        colors: .init(
            mainBackground: .red,
            buttonBackground: .yellow,
            addButtonBackground: .purple
        ),
        images: .init(
            camera: Image(systemName: "camera")
        )
    )
)

// chat view with a full background image  
.chatTheme(
    ChatTheme(
        colors: .init(
            buttonBackground: .yellow,
            addButtonBackground: .purple
        ),
        images: .init(
            background: ChatTheme.Images.Background(
                portraitBackgroundLight: Image("chatBackgroundLight"),
                portraitBackgroundDark: Image("chatBackgroundDark"),
                landscapeBackgroundLight: Image("chatBackgroundLandscapeLight"),
                landscapeBackgroundDark: Image("chatBackgroundLandscapeDark")
            )
    )
)

```
By default the built-in MediaPicker will be auto-customized using the most logical colors from chatTheme. But you can always use `mediaPickerTheme` in a similar fashion to set your own colors.      
  
<img src="https://raw.githubusercontent.com/exyte/media/master/Chat/pic2.png" width="300">

## Large Attachment Support

The library provides full support for uploading multiple attachments larger than 100 MB and for reporting upload status on both the sender’s and receiver’s message views. It offers flexibility in how much progress tracking functionality the client implements, allowing developers to omit percentage-based updates if desired. Sending percentage updates to the receiver requires careful handling, as it involves multiple WebSocket calls to synchronize status between sender and receiver.

*Option 1*

No status is passed to an Attachment. This is the default behavior and shows no progress indicators. If the full attachment is uploaded to a resource server before the message is sent to the receiver, use this method, as it is the simplest and requires no progress tracking.

```swift
Attachment(
  fullUploadStatus: Attachment.UploadStatus? = nil
)
```

*Option 2*

A progress indicator is displayed without a percentage. Most chat applications handle multiple large (100 MB+) files, which may take several minutes to upload. In these cases, Option 1 results in a poor user experience because the receiver has no indication that the files are being uploaded. Option 2 allows both the sender and receiver to see a generic progress indicator during the upload.

```swift
Attachment(
  fullUploadStatus: Attachment.UploadStatus? = Attachment.UploadStatus.inProgress(nil)
)
```

*Option 3*: 

A progress indicator is displayed with a percentage. This option provides the best user experience, as it shows the progress of the upload. However, it adds implementation complexity: both the sender and receiver must remain synchronized through multiple WebSocket updates (e.g., 10%, 20%, …). For production-quality chat applications, implementing this option is recommended.

```swift
Attachment(
  fullUploadStatus: Attachment.UploadStatus? = Attachment.UploadStatus.inProgress(0)
)
```

When implementing status updates via Option 2/3 the following status updates need to be handled by the client:

```swift
// When the upload completes, send a final message to stop displaying the progress indicator.
let completeUpload = Attachment(fullUploadStatus: Attachment.UploadStatus.complete)
sendToServer(initialProgress)

// If the user cancels an attachment upload, report this to the receiver.
let cancelUpload = Attachment(fullUploadStatus: Attachment.UploadStatus.cancelled)
sendToServer(cancelUpload)

// If the upload to the resource server fails, send an error status to the receiver.
let errorUpload = Attachment(fullUploadStatus: Attachment.UploadStatus.error)
sendToServer(errorUpload)
```

## Sticker Keyboard

You can pick and send animated gifs via the integrated sticker keyboard. In order to use this functionality a client id must be granted via the [Giphy Developers](https://developers.giphy.com/) site.

To include the sticker keyboard:

```swift
.setAvailableInputs([.text, .giphy])
.giphyConfig(
    GiphyConfiguration(
        giphyKey: "client id",
        mediaTypeConfig: [.recents, .gifs, .stickers, .clips],
        showAttributionMark: true
    )
)
```

To approve a production client Id for your app, Giphy requires that you include a "Powered By GIPHY" attribution mark, see [attribution mark requirement](https://support.giphy.com/hc/en-us/articles/360035158592-What-conditions-does-my-app-project-need-to-meet-in-order-to-get-a-production-API-Key). Setting the showAttributionMark in the GiphyConfiguration struct will include a small overlay image on the giphy picker which meets the requirement needed for a production client key.


## Localization

You can localize the inputs using the standard SwiftUI localization process, add the input strings to each languages Localizable.strings file.  
The library uses the following text that can be localized:

- Type a message...
- Add signature...
- Cancel
- Recents
- Waiting for network
- Recording...
- Reply to

## Image Caching with Cache Keys

The Chat framework uses Kingfisher for efficient image caching. You can provide custom cache keys. By default, the cache key is the URL of the image.

### User Avatar Cache Keys

When creating a `User`, you can specify a custom cache key for the avatar image:

```swift
let user = User(
    id: "user123",
    name: "John Doe",
    avatarURL: URL(string: "https://example.com/avatar.jpg"),
    avatarCacheKey: "user_avatar_123", // Custom cache key
    isCurrentUser: false
)
```

### Attachment Cache Keys

For `Attachment` objects, you can specify separate cache keys for thumbnail and full-size images:

```swift
let attachment = Attachment(
    id: "attachment456",
    thumbnail: URL(string: "https://example.com/thumb.jpg"),
    full: URL(string: "https://example.com/full.jpg"),
    type: .image,
    thumbnailCacheKey: "thumb_456", // Cache key for thumbnail
    fullCacheKey: "full_456"        // Cache key for full image
)
```

## Examples
There are 2 example projects:    
- One has a simple bot posting random text/media messages every 2 seconds. It has no back end and no local storage. Every new start is clean and fresh.     
- Another has an integration with Firestore data base. It has all the necessary back end support, including storing media and audio messages, unread messages counters, etc. You'll have to create your own Firestore app and DB. Also replace `GoogleService-Info` with your own. After that you can test on multiple sims/devices.    

To set up the Firestore example:
1. Create your Firebase app at https://console.firebase.google.com/
2. Create a Firestore database (for lightweight text data) - see https://firebase.google.com/docs/firestore/manage-data/add-data
3. Create a Cloud Storage bucket (for images and voice recordings) - see https://firebase.google.com/docs/storage/web/start

## Running the Examples

To try the Chat examples:
- Clone the repo `https://github.com/exyte/Chat.git`
- Open `ChatExample.xcodeproj` or `ChatFirestoreExample.xcodeproj` in Xcode
- Try it!

## Installation

### [Swift Package Manager](https://swift.org/package-manager/)

```swift
dependencies: [
    .package(url: "https://github.com/exyte/Chat.git")
]
```

## Requirements

* iOS 17+
* Xcode 15+

## Our other open source SwiftUI libraries
[PopupView](https://github.com/exyte/PopupView) - Toasts and popups library    
[AnchoredPopup](https://github.com/exyte/AnchoredPopup) - Anchored Popup grows "out" of a trigger view (similar to Hero animation)   
[Grid](https://github.com/exyte/Grid) - The most powerful Grid container    
[ScalingHeaderScrollView](https://github.com/exyte/ScalingHeaderScrollView) - A scroll view with a sticky header which shrinks as you scroll    
[AnimatedTabBar](https://github.com/exyte/AnimatedTabBar) - A tabbar with a number of preset animations   
[MediaPicker](https://github.com/exyte/mediapicker) - Customizable media picker     
[OpenAI](https://github.com/exyte/OpenAI) Wrapper lib for [OpenAI REST API](https://platform.openai.com/docs/api-reference/introduction)    
[AnimatedGradient](https://github.com/exyte/AnimatedGradient) - Animated linear gradient     
[ConcentricOnboarding](https://github.com/exyte/ConcentricOnboarding) - Animated onboarding flow    
[FloatingButton](https://github.com/exyte/FloatingButton) - Floating button menu    
[ActivityIndicatorView](https://github.com/exyte/ActivityIndicatorView) - A number of animated loading indicators    
[ProgressIndicatorView](https://github.com/exyte/ProgressIndicatorView) - A number of animated progress indicators    
[FlagAndCountryCode](https://github.com/exyte/FlagAndCountryCode) - Phone codes and flags for every country    
[SVGView](https://github.com/exyte/SVGView) - SVG parser    
[LiquidSwipe](https://github.com/exyte/LiquidSwipe) - Liquid navigation animation







# Embie — What It Is and How It Works

## 1. What is Embie?

Embie is a **Text and Voice AI companion** where you interact with your own personalized, AI companion friend.

Rather than interacting with an AI as a generic chatbot, you have a specific character that has its own personality, name, appearance, and way of communicating with you.

The core idea is that the Embie becomes a **personal guide/companion** that gets to know you over time.

It is designed for ongoing, open-ended conversations rather than isolated questions and answers. OpenAI describes it as an AI companion where the character learns from conversations over time. ([OpenAI][1])

The concept of a "guide" is intentionally broader than simply calling it a therapist, life coach, or friend. People can use it in different ways:

* Talk through what's happening in their life.
* Discuss their emotions or what is stressing them.
* Get advice or perspective.
* Think through decisions.
* Talk casually.
* Get practical help with everyday problems.
* Set goals and work toward them.
* Ask questions and get recommendations.

The important distinction is that **the same companion can move between emotional and practical conversations**.

---

# 2. Your Embie

When you use the app, you get your own Embie.

You personalize the experience around this character, including its identity/name.

The character isn't supposed to feel like a generic AI interface. It is intended to feel more like **someone who knows you and has an ongoing relationship with you**.


---

# 3. How you interact with it

Embie is **Text and Voice-based**.

You talk to your Embie, and it talks back.

Voice is a major part of the experience rather than simply an additional input method.
But for now we only working on supporting text first, voice comes later

The goal is to make the interaction feel like a natural conversation rather than:

> type prompt → wait → read answer

---

# 4. The onboarding conversation

When you first use Embie, you don't simply start asking it random questions.

The app has an onboarding process where the onboarding questions get you the the embie personalized a bit based on those answers to fix the cold start thing. so we ask questions about you.

For example:

* What are your hopes and dreams?
* What are you interested in?
* What do you care about?
* What are you stressed about?
* What goals do you have?
* What would you like to accomplish?

This gives the system information that can later be used to personalize conversations and recommendations.

---

# 5. The central feature: memory

One of the most important things that differentiates Embie from a generic chatbot is **persistent memory**.

The Embie remembers things you tell it.

For example, you might tell it:

* You're stressed about finding summer camp for your children.
* You want to start a business.
* You're planning a trip.
* You are interested in a particular subject.
* You have a specific goal.
* Something important happened to you.

Later, the Embie can bring that information back into the conversation.

The idea isn't simply to maintain a transcript of everything you've ever said. Embie has built a dedicated memory system intended to retrieve the **relevant things about you at the right time**.

Memories are retrieved dynamically during conversations rather than simply stuffing an enormous historical transcript into every prompt.

---

# 6. Memory is contextual

The important part isn't just:

> "I remember that you said X."

The goal is:

> "I remember X, and I know when X is relevant to what we're talking about now."

For example:

You might tell your Embie that you're trying to start a café.

Later, when you're talking about something related to restaurants, entrepreneurship, business podcasts, or your plans, Embie may connect the current conversation to that previous goal.

Embie searching the internet to find recommendations based on things the user has previously told it.

For example, if someone says they want to start a business, the Embie might later find a relevant podcast or other resource and recommend it based on that personal context. 

---

# 7. Personality

Each Embie has a defined personality.

The personality isn't supposed to be completely static, though.

The system starts with a specific character/personality foundation and then adapts its communication to the user.

For example:

* If you're playful, it can be playful.
* If you're serious, it can become more grounded.
* If you're casual, it can communicate casually.
* If you use slang, it can mirror that style.
* If you communicate formally, it can respond more formally.

the system adapting to things such as capitalization, slang, swearing, and the overall style of the user's messages.

The goal is for the Embie to **feel like it is adapting to you rather than forcing everyone into the same personality**.

---

# 8. Emotional + practical assistance

Embie isn't positioned as purely an emotional companion or purely a productivity assistant.

The interesting part is the combination.

A conversation might start with something emotional:

> "I'm really stressed."

The reason might then turn out to be something practical:

> "I haven't figured out the kids' summer camp."

So the Embie can move from:

**emotional context → understanding the problem → helping solve the practical problem.**

The interview describes this combination as one of the most valuable parts of the product. 

---

# 9. Everyday practical help

Embie can also be useful for ordinary everyday tasks.

Examples mentioned in the interview include:

* Cooking help.
* Figuring out how to cut or prepare food.
* Planning meals.
* Planning grocery lists.
* Planning summer camp.
* Organizing things around the house.
* Finding information.
* Making recommendations.
* Helping think through plans.

The cooking example is particularly illustrative: someone can be cooking and simply talk to their Embie about how to prepare something, receive an answer, and continue the conversation naturally. 

The broader goal is to help with the things occupying your mind in everyday life.

The team describes this metaphorically as **"closing tabs in your mind."**

Modern life leaves people with many unresolved things running in the background:

* Things they need to remember.
* Decisions they need to make.
* Plans they haven't made.
* Tasks they haven't completed.
* Things they're worried about.

Embie is intended to help reduce that mental load.

---

# 10. Intentions

Embie has a feature called **Intentions**.

Based on what the Embie knows about you and what you've discussed, it can come up with intentions for the day.

For example, if you've been talking about a particular goal or problem, your Embie can use that context when suggesting what you might focus on.

This makes the interaction more continuous than simply opening an AI chatbot and starting from zero every time. 

---

# 11. Reflections

Embie can also generate **reflections about you** based on what it has observed throughout your conversations.

The idea is that, because the Embie has accumulated context about you, it can reflect back patterns or observations rather than simply answering the immediate question.

This contributes to the feeling that the Embie is actually getting to know you over time. 

---

# 12. Recommendations

Embie can use what it knows about you to make personalized recommendations.

For example:

1. You tell Embie about a goal.
2. The information becomes part of its understanding of you.
3. Later, it can search for something relevant.
4. It can recommend a podcast, resource, idea, or other content based on your particular situation.

The important part is that the recommendation isn't necessarily based only on the current prompt.

It can be based on **your longer-term context and goals**. 

---

# 13. Conversations can change direction

Embie is designed for conversations that don't follow a rigid structure.

You might be talking about work and suddenly start talking about your family.

Then you might jump to something you're worried about.

Then you might ask a completely practical question.

The system needs to maintain the appropriate context while adapting to the new subject.

This is one of the reasons Embie's architecture emphasizes reconstructing context on every conversational turn rather than relying on a static cached prompt. OpenAI says each turn can incorporate recent conversation summaries, the character/persona, retrieved memories, tone guidance, and real-time app signals. ([OpenAI][1])

---

# 14. How Embie manages context

Embie **reconstructs its context window on every turn** rather than simply carrying a cached prompt forward.

That reconstruction can include:

* Recent conversation summary.
* The Embie's persona.
* Retrieved memories about the user.
* Tone instructions.
* Real-time application signals.

This allows the system to change context quickly when the user changes topics. 

---

# 16. How the memory system works technically

Embie's memory system goes beyond storing a transcript.

OpenAI describes a system where memories are embedded using **text-embedding-3-large** and stored in **Turbopuffer**, allowing relevant memories to be retrieved quickly during a conversation. ([OpenAI][1])

The system can also generate questions about the user internally to help retrieve relevant memories.

For example, if the current conversation makes the question:

> "Who is the user's spouse?"

relevant, that can be used to retrieve the appropriate stored memory.

Embie also runs a nightly memory-compression process that removes low-value or redundant information and resolves contradictions.

The objective is to maintain a **useful representation of the user**, rather than accumulating an ever-growing transcript.

---


# 17. What Embie is ultimately trying to become

The long-term concept is an **always-available personal AI companion/guide** that becomes part of someone's daily life.

Instead of only opening the app when you have a question, you might naturally talk to it:

* On your way to work.
* In the morning.
* When planning your day.
* When you're anxious about something.
* When planning the weekend.
* When you need advice.
* When you need to solve an everyday problem.
* When you simply want someone to talk to.

The Embie can then use everything it has learned about you to provide increasingly personalized help.

The product is therefore less about:

> **"Ask AI a question."**

and more about:

> **"Have an ongoing relationship with an AI that knows you."**

---

# The core Embie model

A useful way to reduce the whole product to one diagram is:

```text
                    ┌──────────────────────┐
                    │        USER          │
                    │                      │
                    │  Talks about life,   │
                    │  goals, problems,    │
                    │  plans, interests    │
                    └──────────┬───────────┘
                               │
                               │ Voice
                               ▼
                    ┌──────────────────────┐
                    │        Embie         │
                    │                      │
                    │ Personalized AI      │
                    │ Character / Guide     │
                    └──────────┬───────────┘
                               │
             ┌─────────────────┼─────────────────┐
             │                 │                 │
             ▼                 ▼                 ▼
        Conversation        Memory          Personality
          Context          System             System
             │                 │                 │
             └─────────────────┼─────────────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │  PERSONALIZED        │
                    │  RESPONSE            │
                    │                      │
                    │ Voice + character +  │
                    │ relevant memories +  │
                    │ appropriate tone     │
                    └──────────┬───────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │  LEARNS OVER TIME    │
                    │                      │
                    │ Goals                │
                    │ Preferences          │
                    │ Facts                │
                    │ Patterns             │
                    │ Emotional context    │
                    └──────────────────────┘
```

So the key product loop is:

**Talk → Understand → Remember → Personalize → Help → Learn → Repeat.**
