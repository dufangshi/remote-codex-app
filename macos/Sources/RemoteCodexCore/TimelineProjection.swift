import Foundation

public enum TimelineProjection {
    public static func merge(detail: [HistoryItem], summary: [HistoryItem]) -> [HistoryItem] {
        let updates = Dictionary(summary.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let ids = Set(detail.map(\.id))
        return detail.map { item in
            guard let update = updates[item.id], !update.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ["userMessage", "agentMessage", "assistantMessage", "assistant"].contains(update.kind) else { return item }
            return update
        } + summary.filter { !ids.contains($0.id) }
    }
    public static func visible(_ items: [HistoryItem]) -> [HistoryItem] {
        items.filter { !["agentMessage", "assistantMessage", "assistant", "reasoning"].contains($0.kind) || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    public static func groups(_ items: [HistoryItem]) -> [[HistoryItem]] {
        var result: [[HistoryItem]] = []
        let grouped: Set<String> = ["commandExecution", "toolCall", "agentToolCall", "skillToolCall"]
        for item in visible(items) {
            if grouped.contains(item.kind), result.last?.last?.kind == item.kind { result[result.count - 1].append(item) }
            else { result.append([item]) }
        }
        return result
    }
    public static func label(_ item: HistoryItem) -> String {
        [item.previewText, item.text, item.title].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? item.kind
    }
}
