//
//  UIList.swift
//  
//
//  Created by Alisa Mylnikova on 24.02.2023.
//

import SwiftUI
import Combine

struct UIList<MessageContent: View>: UIViewRepresentable {

    typealias MessageBuilderParamsClosure = ChatView<MessageContent, InputView, DefaultMessageMenuAction>.MessageBuilderParamsClosure

    @Environment(\.chatTheme) var theme

    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var inputViewModel: InputViewModel

    @Binding var pendingScrollTo: ScrollToParams?
    @Binding var isScrolledToBottom: Bool
    @Binding var tableContentHeight: CGFloat

    // MARK: - View builders

    let messageBuilder: MessageBuilderParamsClosure
    let mainHeaderBuilder: (()->AnyView)?
    let dateHeaderBuilder: ((Date)->AnyView)?

    // MARK: - Data / type

    let type: ChatType
    let sections: [MessagesSection]
    let ids: [String]

    // MARK: - Customization

    let chatParams: ChatCustomizationParameters
    let messageParams: MessageCustomizationParameters

    // MARK: - State

    @State private var isScrolledToTop = false
    @State private var updateQueue = UpdateQueue()
    @State private var transaction = TableUpdateTransaction()

    @State private var cancellables = Set<AnyCancellable>()

    func makeUIView(context: Context) -> UITableView {
        let style = mainHeaderBuilder != nil || chatParams.showDateHeaders ? UITableView.Style.grouped : .plain
        let tableView = UITableView(frame: .zero, style: style)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.transform = CGAffineTransform(rotationAngle: (type == .conversation ? .pi : 0))

        tableView.showsVerticalScrollIndicator = false
        tableView.estimatedSectionHeaderHeight = 1
        tableView.estimatedSectionFooterHeight = UITableView.automaticDimension
        tableView.backgroundColor = UIColor(theme.contentBG)
        tableView.scrollsToTop = false
        tableView.isScrollEnabled = chatParams.isScrollEnabled
        tableView.keyboardDismissMode = chatParams.keyboardDismissMode
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionHeaderHeight = 0
        tableView.sectionFooterHeight = 0
        tableView.tableHeaderView = nil
        tableView.tableFooterView = UIView(frame: .zero)

        transaction.updateQueue = updateQueue
        chatParams.onTransactionReady?(transaction)

        return tableView
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        // The quick-attach fan is driven by a drag that starts on the composer; letting the list
        // scroll underneath it steals the gesture and moves the target photos.
        let shouldScroll = chatParams.isScrollEnabled && !inputViewModel.isScrollLocked
        if tableView.isScrollEnabled != shouldScroll {
            tableView.isScrollEnabled = shouldScroll
        }

        if !chatParams.isScrollEnabled {
            DispatchQueue.main.async {
                tableContentHeight = tableView.contentSize.height
            }
        }

        if tableView.contentInset != chatParams.contentInsets {
            let previousMetrics = tableView.verticalScrollMetrics
            let shouldMaintainNewestEdge =
                type == .conversation
                && (
                    isScrolledToBottom
                    || previousMetrics.isAtMinimum(tableView.contentOffset.y)
                )

            tableView.contentInset = chatParams.contentInsets
            tableView.layoutIfNeeded()

            if shouldMaintainNewestEdge {
                let minimumOffset = tableView.verticalScrollMetrics.minimumOffset
                if abs(tableView.contentOffset.y - minimumOffset)
                    > ScrollMetrics.edgeTolerance {
                    tableView.setContentOffset(
                        CGPoint(x: 0, y: minimumOffset),
                        animated: false
                    )
                }
            }
        }

        context.coordinator.chatParams = chatParams

        let needToUpdateSections = context.coordinator.latestUpdateSections != sections
        let needToScroll = pendingScrollTo != nil
        let animationMode = updateQueue.getAnimationMode()

        //print("changes animationMode: \(animationMode) needToUpdateSections: \(needToUpdateSections), needToScroll: \(needToScroll), pendingScrollTo: \(pendingScrollTo)")

        guard needToUpdateSections || needToScroll else { return }

        updateQueue.markRealUpdate()
        context.coordinator.latestUpdateSections = sections
        context.coordinator.updateInProgress = true

        updateQueue.createJob {
            Task { @MainActor in
                if needToUpdateSections {
                    if animationMode == .none
                        || context.coordinator.sections.isEmpty
                        || pendingScrollTo != nil { // if we're gonna scroll later, then update cells without animation, and animate scrolling later
                        updateTableNoAnimation(tableView, context.coordinator)
                    } else if animationMode == .natural,
                              tableView.verticalScrollMetrics.isAtMinimum(
                                tableView.contentOffset.y
                              ) {
                        await updateTableWithAnimation(tableView, context.coordinator)
                    } else {
                        // if transaction.animationMode == .keepStable
                        // || (transaction.animationMode == .natural && tableView.contentOffset != .zero) {
                        await performInsertPreservingOffset(tableView, context.coordinator)
                    }
                }

                if needToScroll, let scrollToParams = pendingScrollTo {
                    pendingScrollTo = nil // reset to only scroll once

                    let perform = {
                        performScrollTo(tableView, scrollToParams: scrollToParams)
                    }

                    if animationMode == .natural,
                       tableView.verticalScrollMetrics.isAtMinimum(
                        tableView.contentOffset.y
                       ) {
                        await withCheckedContinuation { continuation in
                            UIView.animate(withDuration: 0.25) {
                                perform()
                            } completion: { _ in
                                continuation.resume()
                            }
                        }
                    } else {
                        perform()
                    }
                }

                tableView.beginUpdates()
                context.coordinator.updateInProgress = false
                tableView.endUpdates()
                tableView.relayoutHeadersFooters()
            }
        }
    }

    // MARK: scroll to

    func performScrollTo(_ tableView: UITableView, scrollToParams: ScrollToParams) {
        switch scrollToParams.scrollTo {
        case .messageID(let messageID, let position, let offset):
            scrollToRow(tableView, messageID: messageID, position: position, additionalOffset: offset)
        case .tableOffset(let offset):
            tableView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        case .newestMessage:
            tableView.setContentOffset(
                CGPoint(x: 0, y: tableView.verticalScrollMetrics.minimumOffset),
                animated: false
            )
        case .oldestMessage:
            guard tableView.numberOfSections > 0 else { return }

            for section in stride(
                from: tableView.numberOfSections - 1,
                through: 0,
                by: -1
            ) {
                let rowCount = tableView.numberOfRows(inSection: section)
                guard rowCount > 0 else { continue }

                tableView.scrollToRow(
                    at: IndexPath(row: rowCount - 1, section: section),
                    at: .bottom,
                    animated: false
                )
                return
            }
        }
    }

    @MainActor
    func scrollToRow(_ tableView: UITableView, messageID: String, position: UITableView.ScrollPosition, additionalOffset: CGFloat) {
        guard let indexPath = indexPath(for: messageID, in: sections),
              let rect = tableView.rectForRow(at: indexPath) as CGRect? else { return }

        let adjustedPosition =
        (position == .middle || type == .comments) ? position
        : position == .bottom ? .top: .bottom

        let metrics = tableView.verticalScrollMetrics
        let baseY: CGFloat
        switch adjustedPosition {
        case .top:
            baseY = rect.minY - tableView.adjustedContentInset.top
        case .middle:
            baseY = metrics.centeredOffset(forItemMidY: rect.midY)
        default:
            baseY = rect.maxY - tableView.bounds.height + tableView.adjustedContentInset.bottom
        }

        let targetY = baseY + additionalOffset
        let clampedY = metrics.clamped(targetY)

        tableView.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
    }

    func indexPath(for id: String, in sections: [MessagesSection]) -> IndexPath? {
        for (sectionIndex, section) in sections.enumerated() {
            if let rowIndex = section.rows.firstIndex(where: { $0.message.id == id }) {
                return IndexPath(row: rowIndex, section: sectionIndex)
            }
        }
        return nil
    }

    // MARK: update table

    func performInsertPreservingOffset(_ tableView: UITableView, _ coordinator: Coordinator) async {
        guard let firstVisibleIndexPath = tableView.indexPathsForVisibleRows?.first,
              let preservedVisibleRect = tableView.rectForRow(at: firstVisibleIndexPath) as CGRect? else { return }

        let firstVisibleRow = coordinator.sections[firstVisibleIndexPath.section].rows[firstVisibleIndexPath.row]
        let preservedVisibleMessageID = firstVisibleRow.message.id
        let preservedOffset = tableView.contentOffset.y

        coordinator.sections = sections

        CATransaction.setDisableActions(true)

        tableView.reloadData()
        tableView.layoutIfNeeded()

        guard let newIndexPath = indexPath(for: preservedVisibleMessageID, in: sections) else { return }
        let newRectForCell = tableView.rectForRow(at: newIndexPath)
        let newOffset = preservedOffset + (newRectForCell.minY - preservedVisibleRect.minY)
        //print("firstVisibleIndexPath: \(firstVisibleIndexPath), newIndexPath: \(newIndexPath), preservedOffset: \(preservedOffset), newOffset: \(newOffset), preservedVisibleRect: \(preservedVisibleRect), newRectForCell: \(newRectForCell)")
        tableView.setContentOffset(CGPoint(x: 0, y: newOffset), animated: false)

        tableView.relayoutHeadersFooters()
    }

    @MainActor
    private func updateTableNoAnimation(_ tableView: UITableView, _ coordinator: Coordinator) {
        coordinator.sections = sections

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        UIView.performWithoutAnimation {
            tableView.reloadData()
            tableView.layoutIfNeeded()
        }

        CATransaction.commit()
    }

    @MainActor
    private func updateTableWithAnimation(_ tableView: UITableView, _ coordinator: Coordinator) async {
        let prevSections = coordinator.sections
        let splitInfo = await performSplitInBackground(prevSections, sections)
        await applyOperations(tableView, splitInfo: splitInfo) {
            coordinator.sections = $0
        }
    }

    nonisolated private func performSplitInBackground(_ prevSections: [MessagesSection], _ sections: [MessagesSection]) async -> SplitInfo {
        await withCheckedContinuation { continuation in
            Task.detached {
                let result = SplitInfo.operationsSplit(oldSections: prevSections, newSections: sections)
                continuation.resume(returning: result)
            }
        }
    }

    @MainActor
    private func applyOperations(_ tableView: UITableView, splitInfo: SplitInfo, updateContextClosure: ([MessagesSection])->()) async {
        // step 0: preparation
        // prepare intermediate sections and operations
//        print("whole appliedDeletes:\n", formatSections(splitInfo.appliedDeletes), "\n")
//        print("whole appliedDeletesSwapsAndEdits:\n", formatSections(splitInfo.appliedDeletesSwapsAndEdits), "\n")
//        print("whole final sections:\n", formatSections(sections), "\n")
//
//        print("operations delete:\n", splitInfo.deleteOperations.map { $0.description })
//        print("operations swap:\n", splitInfo.swapOperations.map { $0.description })
//        print("operations edit:\n", splitInfo.editOperations.map { $0.description })
//        print("operations insert:\n", splitInfo.insertOperations.map { $0.description })

        await performBatchTableUpdates(tableView) {
            // step 1: deletes
            // delete sections and rows if necessary
            //print("1 apply deletes", runID)
            updateContextClosure(splitInfo.appliedDeletes)
            //context.coordinator.sections = appliedDeletes
            for operation in splitInfo.deleteOperations {
                applyOperation(operation, tableView: tableView)
            }
        }
        //print("1 finished deletes", runID)

        await performBatchTableUpdates(tableView) {
            // step 2: swaps
            // swap places for rows that moved inside the table
            // (example of how this happens. send two messages: first m1, then m2. if m2 is delivered to server faster, then it should jump above m1 even though it was sent later)
            //print("2 apply swaps", runID)
            updateContextClosure(splitInfo.appliedDeletesSwapsAndEdits) // NOTE: this array already contains necessary edits, but won't be a problem for appplying swaps
            for operation in splitInfo.swapOperations {
                applyOperation(operation, tableView: tableView)
            }
        }
        //print("2 finished swaps", runID)

        await performBatchTableUpdates(tableView) {
            // step 3: edits
            // check only sections that are already in the table for existing rows that changed and apply only them to table's dataSource without animation
            //print("3 apply edits", runID)
            updateContextClosure(splitInfo.appliedDeletesSwapsAndEdits)

            for operation in splitInfo.editOperations {
                applyOperation(operation, tableView: tableView)
            }
        }
        //print("3 finished edits", runID)

        // step 4: inserts
        // apply the rest of the changes to table's dataSource, i.e. inserts
        //print("4 apply inserts", runID)
        updateContextClosure(sections)

        let animated = isScrolledToBottom || isScrolledToTop
        await performBatchTableUpdates(tableView) {
            for operation in splitInfo.insertOperations {
                applyOperation(operation, tableView: tableView, animateInserts: animated)
            }
        }
        //print("4 finished inserts", runID)

        tableView.relayoutHeadersFooters()

        if !chatParams.isScrollEnabled {
            tableContentHeight = tableView.contentSize.height
        }
    }

    private func isSectionOperation(_ operation: Operation) -> Bool {
        switch operation {
        case .deleteSection, .insertSection:
            return true
        case .delete, .insert, .swap, .edit, .editChangingHeight, .editStreaming:
            return false
        }
    }

    // MARK: - Operations

    enum Operation {
        case deleteSection(Int)
        case insertSection(Int)

        case delete(Int, Int)
        case insert(Int, Int)
        case swap(Int, Int, Int)

        case edit(Int, Int) // reload the element without animation (otherwise it blinks)
        case editChangingHeight(Int, Int) // reload the element with simple animation
        case editStreaming(Int, Int) // update content and smoothly recalculate self-sizing height

        var description: String {
            switch self {
            case .deleteSection(let int):
                return "deleteSection \(int)"
            case .insertSection(let int):
                return "insertSection \(int)"
            case .delete(let int, let int2):
                return "delete section \(int) row \(int2)"
            case .insert(let int, let int2):
                return "insert section \(int) row \(int2)"
            case .swap(let int, let int2, let int3):
                return "swap section \(int) rowFrom \(int2) rowTo \(int3)"
            case .edit(let int, let int2):
                return "edit section \(int) row \(int2)"
            case .editChangingHeight(let int, let int2):
                return "editChangingHeight section \(int) row \(int2)"
            case .editStreaming(let int, let int2):
                return "editStreaming section \(int) row \(int2)"
            }
        }
    }

    func applyOperation(_ operation: Operation, tableView: UITableView, animateInserts: Bool = true) {
        switch operation {
        case .deleteSection(let section):
            tableView.deleteSections([section], with: .automatic)
        case .insertSection(let section):
            tableView.insertSections([section], with: .top)
        case .delete(let section, let row):
            tableView.deleteRows(at: [IndexPath(row: row, section: section)], with: .top)
        case .insert(let section, let row):
            tableView.insertRows(at: [IndexPath(row: row, section: section)], with: animateInserts ? .top : .none)
        case .swap(let section, let rowFrom, let rowTo):
            tableView.deleteRows(at: [IndexPath(row: rowFrom, section: section)], with: .top)
            tableView.insertRows(at: [IndexPath(row: rowTo, section: section)], with: .top)
        case .edit(let section, let row):
            tableView.reconfigureRows(at: [IndexPath(row: row, section: section)])
        case .editChangingHeight(let section, let row):
            tableView.reloadRows(at: [IndexPath(row: row, section: section)], with: .automatic)
        case .editStreaming(let section, let row):
            tableView.reconfigureRows(at: [IndexPath(row: row, section: section)])
            UIView.animate(
                withDuration: 0.16,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
            ) {
                tableView.beginUpdates()
                tableView.endUpdates()
                tableView.layoutIfNeeded()
            }
        }
    }

    // MARK: - Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel,
            inputViewModel: inputViewModel,
            isScrolledToBottom: $isScrolledToBottom,
            isScrolledToTop: $isScrolledToTop,

            messageBuilder: messageBuilder,
            mainHeaderBuilder: mainHeaderBuilder,
            dateHeaderBuilder: dateHeaderBuilder,

            type: type,
            sections: sections,
            ids: ids,

            chatParams: chatParams,
            messageParams: messageParams,
            mainBackgroundColor: theme.contentBG
        )
    }

    class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {

        @ObservedObject var viewModel: ChatViewModel
        @ObservedObject var inputViewModel: InputViewModel

        @Binding var isScrolledToBottom: Bool
        @Binding var isScrolledToTop: Bool

        // MARK: - View builders

        let messageBuilder: MessageBuilderParamsClosure
        let mainHeaderBuilder: (()->AnyView)?
        let dateHeaderBuilder: ((Date)->AnyView)?

        // MARK: - Data / type

        let type: ChatType
        var sections: [MessagesSection] {
            didSet {
                olderPaginationTriggerArmed = true
                newerPaginationTriggerArmed = true
                updatePaginationTargetMessageIDs()
            }
        }
        let ids: [String]

        // MARK: - Customization

        var chatParams: ChatCustomizationParameters {
            didSet {
                updatePaginationTargetMessageIDs()
            }
        }
        let messageParams: MessageCustomizationParameters
        let mainBackgroundColor: Color

        var updateInProgress: Bool = false
        /// call pagination handler when this row is reached
        /// without this there is a bug: during new cells insertion willDisplay is called one extra time for the cell which used to be the last one while it is being updated (its position in group is changed from first to middle)
        var olderPaginationTargetMessageID: String?
        var newerPaginationTargetMessageID: String?
        let paginationState = PaginationState()
        private var olderPaginationTriggerArmed = true
        private var newerPaginationTriggerArmed = true

        // helpers to avoid queueing same updates multiple times
        var latestUpdateSections: [MessagesSection] = []

        private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)

        init(
            viewModel: ChatViewModel,
            inputViewModel: InputViewModel,
            isScrolledToBottom: Binding<Bool>,
            isScrolledToTop: Binding<Bool>,

            messageBuilder: @escaping MessageBuilderParamsClosure,
            mainHeaderBuilder: (() -> AnyView)?,
            dateHeaderBuilder: ((Date) -> AnyView)?,

            type: ChatType,
            sections: [MessagesSection],
            ids: [String],

            chatParams: ChatCustomizationParameters,
            messageParams: MessageCustomizationParameters,
            mainBackgroundColor: Color
        ) {
            self.viewModel = viewModel
            self.inputViewModel = inputViewModel
            self._isScrolledToBottom = isScrolledToBottom
            self._isScrolledToTop = isScrolledToTop

            self.messageBuilder = messageBuilder
            self.mainHeaderBuilder = mainHeaderBuilder
            self.dateHeaderBuilder = dateHeaderBuilder

            self.type = type
            self.sections = sections
            self.ids = ids

            self.chatParams = chatParams
            self.messageParams = messageParams
            self.mainBackgroundColor = mainBackgroundColor

            super.init()
            updatePaginationTargetMessageIDs()
        }

        private func updatePaginationTargetMessageIDs() {
            let olderTarget = cellIndexOffset(
                from: chatParams.olderMessagesPaginationHandler
            ).flatMap(messageIDFromOldest(offset:))
            let newerTarget = cellIndexOffset(
                from: chatParams.newerMessagesPaginationHandler
            ).flatMap(messageIDFromNewest(offset:))

            if olderPaginationTargetMessageID != olderTarget {
                olderPaginationTriggerArmed = true
                olderPaginationTargetMessageID = olderTarget
            }
            if newerPaginationTargetMessageID != newerTarget {
                newerPaginationTriggerArmed = true
                newerPaginationTargetMessageID = newerTarget
            }
        }

        private func cellIndexOffset(from handler: PaginationHandler?) -> Int? {
            guard let handler else { return nil }
            guard case .cellIndex(let offset) = handler.triggerType else {
                return nil
            }
            return max(0, offset)
        }

        private func messageIDFromNewest(offset: Int) -> String? {
            var remainingOffset = offset
            for section in sections {
                if remainingOffset < section.rows.count {
                    return section.rows[remainingOffset].message.id
                }
                remainingOffset -= section.rows.count
            }
            return nil
        }

        private func messageIDFromOldest(offset: Int) -> String? {
            var remainingOffset = offset
            for section in sections.reversed() {
                if remainingOffset < section.rows.count {
                    let row = section.rows.count - 1 - remainingOffset
                    return section.rows[row].message.id
                }
                remainingOffset -= section.rows.count
            }
            return nil
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            sections.count
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            sections[section].rows.count
        }

        // MARK: - headers/footers

//        func hasHeaderForSection(_ section: Int) -> Bool {
//            chatParams.showDateHeaders
//            || (section == 0 && mainHeaderBuilder == nil)
//            || (section == sections.count - 1 && chatParams.olderMessagesPaginationHandler != nil)
//            || (section == 0 && chatParams.newerMessagesPaginationHandler != nil)
//        }

        // small optimization: exclude sections that can't possibly have a header/footer
        func hasSectionView(_ section: Int) -> Bool {
            chatParams.showDateHeaders || section == 0 || section == sections.count - 1
        }

        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            hasSectionView(section) ? UITableView.automaticDimension : 0
        }

        func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
            hasSectionView(section) ? UITableView.automaticDimension : 0
        }

        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            hasSectionView(section) ? makeHostingView { sectionHeaderView(section) } : nil
        }

        func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
            hasSectionView(section) ? makeHostingView { sectionFooterView(section) } : nil
        }

        // table's section header: on top of table for .comments, bottom for .conversation
        func sectionHeaderView(_ section: Int) -> some View {
            HeaderView(
                paginationState: paginationState,
                isFirst: section == 0,
                type: type,
                handler: chatParams.newerMessagesPaginationHandler,
                topContent: { self.sectionTopView(section) }
            )
        }

        // table's section footer: at the bottom of table for .comments, top for .conversation
        func sectionFooterView(_ section: Int) -> some View {
            FooterView(
                paginationState: paginationState,
                isLast: section == sections.count - 1,
                type: type,
                handler: chatParams.olderMessagesPaginationHandler,
                topContent: { self.sectionTopView(section) }
            )
        }

        // is on top for both chat styles
        func sectionTopView(_ section: Int) -> some View {
            VStack(spacing: 0) {
                if let mainHeaderBuilder,
                    (section == 0 && type == .comments) ||
                    (section == sections.count - 1 && type == .conversation) {
                    mainHeaderBuilder()
                }
                if chatParams.showDateHeaders {
                    dateViewBuilder(section)
                }
            }
        }

        @ViewBuilder
        func dateViewBuilder(_ section: Int) -> some View {
            if let dateHeaderBuilder {
                dateHeaderBuilder(sections[section].date)
            } else {
                Text(sections[section].formattedDate)
                    .font(.system(size: 11))
                    .padding(.top, 30)
                    .padding(.bottom, 8)
                    .foregroundColor(.gray)
            }
        }

        func makeHostingView<Content: View>(@ViewBuilder _ content: () -> Content) -> UIView? {
            let view = UIHostingController(rootView:
                content().rotationEffect(Angle(degrees: (type == .conversation ? 180 : 0)))
            ).view
            view?.backgroundColor = UIColor(mainBackgroundColor)
            return view
        }

        // MARK: - cells

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let tableViewCell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            tableViewCell.selectionStyle = .none
            tableViewCell.backgroundColor = UIColor(mainBackgroundColor)

            let row = sections[indexPath.section].rows[indexPath.row]
            tableViewCell.contentConfiguration = UIHostingConfiguration {
                ChatMessageView(
                    viewModel: viewModel,
                    messageBuilder: messageBuilder,
                    row: row,
                    chatType: type,
                    messageParams: messageParams,
                    isDisplayingMessageMenu: false
                )
                .background(MessageMenuPreferenceViewSetter(id: row.id))
                .rotationEffect(Angle(degrees: (type == .conversation ? 180 : 0)))
                .applyIf(chatParams.showMessageMenuOnLongPress) {
                    $0.simultaneousGesture(
                        TapGesture().onEnded { } // add empty tap to prevent iOS17 scroll breaking bug (drag on cells stops working)
                    )
                    .onLongPressGesture {
                        // Trigger haptic feedback
                        self.impactGenerator.impactOccurred()
                        // Launch the message menu
                        self.viewModel.messageMenuRow = row
                    }
                }
            }
            .minSize(width: 0, height: 0)
            .margins(.all, 0)

            return tableViewCell
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            if updateInProgress { return }

            lazy var message = sections[indexPath.section].rows[indexPath.row].message
            if let onWillDisplayCell = chatParams.onWillDisplayCell {
                onWillDisplayCell(message)
            }

            if !paginationState.olderInProgress,
               olderPaginationTriggerArmed,
               let messageID = olderPaginationTargetMessageID,
               message.id == messageID,
               let handler = chatParams.olderMessagesPaginationHandler,
               handler.hasMoreToLoad,
               case .cellIndex(_) = handler.triggerType {
                olderPaginationTriggerArmed = false
                performOlderPagination(tableView)
            }

            if !paginationState.newerInProgress,
               newerPaginationTriggerArmed,
               let messageID = newerPaginationTargetMessageID,
               message.id == messageID,
               let handler = chatParams.newerMessagesPaginationHandler,
               handler.hasMoreToLoad,
               case .cellIndex(_) = handler.triggerType {
                newerPaginationTriggerArmed = false
                performNewerPagination(tableView)
            }
        }

        func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let items = type == .conversation ? chatParams.listSwipeActions.trailing : chatParams.listSwipeActions.leading else { return nil }
            guard !items.actions.isEmpty else { return nil }
            let message = sections[indexPath.section].rows[indexPath.row].message
            let conf = UISwipeActionsConfiguration(actions: items.actions.filter({ $0.activeFor(message) }).map { toContextualAction($0, message: message) })
            conf.performsFirstActionWithFullSwipe = items.performsFirstActionWithFullSwipe
            return conf
        }

        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let items = type == .conversation ? chatParams.listSwipeActions.leading : chatParams.listSwipeActions.trailing else { return nil }
            guard !items.actions.isEmpty else { return nil }
            let message = sections[indexPath.section].rows[indexPath.row].message
            let conf = UISwipeActionsConfiguration(actions: items.actions.filter({ $0.activeFor(message) }).map { toContextualAction($0, message: message) })
            conf.performsFirstActionWithFullSwipe = items.performsFirstActionWithFullSwipe
            return conf
        }

        private func toContextualAction(_ item: SwipeActionable, message: Message) -> UIContextualAction {
            let ca = UIContextualAction(style: .normal, title: nil) { (action, sourceView, completionHandler) in
                item.action(message, self.viewModel.messageMenuAction())
                completionHandler(true)
            }
            ca.image = item.render(type: type)

            let bgColor = item.background ?? mainBackgroundColor
            ca.backgroundColor = UIColor(bgColor)

            return ca
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let contentOffset = scrollView.contentOffset.y
            let metrics = scrollView.verticalScrollMetrics

            chatParams.onContentOffsetChange?(contentOffset)
            isScrolledToBottom = metrics.isAtMinimum(contentOffset)
            isScrolledToTop = metrics.isAtMaximum(contentOffset)

            guard !sections.isEmpty,
                  !updateInProgress,
                  let tableView = scrollView as? UITableView else { return }

            updatePaginationTriggerArming(
                tableView,
                contentOffset: contentOffset,
                metrics: metrics
            )

            if !paginationState.olderInProgress,
               olderPaginationTriggerArmed,
               let handler = chatParams.olderMessagesPaginationHandler,
               handler.hasMoreToLoad,
               case let .pixels(distance) = handler.triggerType,
               metrics.isWithinMaximumEdge(contentOffset, distance: distance) {
                olderPaginationTriggerArmed = false
                performOlderPagination(tableView)
            }

            if !paginationState.newerInProgress,
               newerPaginationTriggerArmed,
               let handler = chatParams.newerMessagesPaginationHandler,
               handler.hasMoreToLoad,
               case let .pixels(distance) = handler.triggerType,
               metrics.isWithinMinimumEdge(contentOffset, distance: distance) {
                newerPaginationTriggerArmed = false
                performNewerPagination(tableView)
            }
        }

        private func updatePaginationTriggerArming(
            _ tableView: UITableView,
            contentOffset: CGFloat,
            metrics: ScrollMetrics
        ) {
            let visibleMessageIDs: Set<String> = Set(
                (tableView.indexPathsForVisibleRows ?? []).compactMap { indexPath in
                    guard sections.indices.contains(indexPath.section),
                          sections[indexPath.section].rows.indices.contains(indexPath.row)
                    else {
                        return nil
                    }
                    return sections[indexPath.section].rows[indexPath.row].message.id
                }
            )

            if let handler = chatParams.olderMessagesPaginationHandler {
                switch handler.triggerType {
                case .cellIndex:
                    if let target = olderPaginationTargetMessageID,
                       !visibleMessageIDs.contains(target) {
                        olderPaginationTriggerArmed = true
                    }
                case .pixels(let distance):
                    if !metrics.isWithinMaximumEdge(
                        contentOffset,
                        distance: distance
                    ) {
                        olderPaginationTriggerArmed = true
                    }
                }
            } else {
                olderPaginationTriggerArmed = true
            }

            if let handler = chatParams.newerMessagesPaginationHandler {
                switch handler.triggerType {
                case .cellIndex:
                    if let target = newerPaginationTargetMessageID,
                       !visibleMessageIDs.contains(target) {
                        newerPaginationTriggerArmed = true
                    }
                case .pixels(let distance):
                    if !metrics.isWithinMinimumEdge(
                        contentOffset,
                        distance: distance
                    ) {
                        newerPaginationTriggerArmed = true
                    }
                }
            } else {
                newerPaginationTriggerArmed = true
            }
        }

        func performOlderPagination(_ tableView: UITableView) {
            guard let handler = chatParams.olderMessagesPaginationHandler,
                  !paginationState.olderInProgress else { return }

            olderPaginationTriggerArmed = false
            paginationState.olderInProgress = true
            tableView.relayoutHeadersFooters()

            Task { @MainActor in
                await handler.handleClosure()

                if paginationState.olderInProgress {
                    paginationState.olderInProgress = false
                    if !updateInProgress {
                        tableView.relayoutHeadersFooters()
                    }
                }
            }
        }

        func performNewerPagination(_ tableView: UITableView) {
            guard let handler = chatParams.newerMessagesPaginationHandler,
                  !paginationState.newerInProgress else { return }

            newerPaginationTriggerArmed = false
            paginationState.newerInProgress = true
            tableView.relayoutHeadersFooters()

            Task { @MainActor in
                await handler.handleClosure()

                if paginationState.newerInProgress {
                    paginationState.newerInProgress = false
                    if !updateInProgress {
                        tableView.relayoutHeadersFooters()
                    }
                }
            }
        }
    }

    func formatRow(_ row: MessageRow) -> String {
        String(
            "id: \(row.id) text: \(String(row.message.attributedText.characters)) status: \(row.message.status ?? .none) date: \(row.message.createdAt) position in user group: \(row.positionInUserGroup) position in messages section: \(row.positionInMessagesSection) trigger: \(row.message.triggerRedraw)"
        )
    }

    func formatSections(_ sections: [MessagesSection]) -> String {
        var res = "(\(sections.count))(\(sections.map{$0.rows.count})){\n"
        for section in sections.reversed() {
            res += String("\t{\n")
            for row in section.rows {
                res += String("\t\t\(formatRow(row))\n")
            }
            res += String("\t}\n")
        }
        res += String("}")
        return res
    }
}

private extension UIScrollView {
    var verticalScrollMetrics: ScrollMetrics {
        ScrollMetrics(
            contentHeight: contentSize.height,
            viewportHeight: bounds.height,
            adjustedTopInset: adjustedContentInset.top,
            adjustedBottomInset: adjustedContentInset.bottom
        )
    }
}
