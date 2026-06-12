import CodeMode

public enum CodeModeEvalToolCallGrader {
    public static func orderedToolCalls(
        _ toolCalls: [CodeModeEvalToolCall],
        expectedOrder: [CodeModeEvalToolName]
    ) -> [CodeModeEvalToolCall] {
        var start = toolCalls.startIndex
        var matches: [CodeModeEvalToolCall] = []

        for expectedTool in expectedOrder {
            guard let matchIndex = toolCalls[start...].firstIndex(where: { $0.tool == expectedTool }) else {
                break
            }
            matches.append(toolCalls[matchIndex])
            start = toolCalls.index(after: matchIndex)
        }

        return matches
    }
}
