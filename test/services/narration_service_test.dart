import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import 'package:engram/src/services/narration_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAnthropicClient extends Mock implements AnthropicClient {}

class FakeCreateMessageRequest extends Fake implements CreateMessageRequest {}

/// Helper to build a Message with a tool use block for generate_narration.
Message _narrationToolUseMessage(Map<String, dynamic> input) {
  return Message(
    id: 'msg-narr-test',
    role: MessageRole.assistant,
    stopReason: StopReason.toolUse,
    content: MessageContent.blocks([
      Block.toolUse(id: 'tu-1', name: 'generate_narration', input: input),
    ]),
    model: 'claude-sonnet-4-5-20250929',
    type: 'message',
    usage: const Usage(inputTokens: 100, outputTokens: 200),
  );
}

void main() {
  late MockAnthropicClient mockClient;
  late NarrationService service;

  setUpAll(() {
    registerFallbackValue(FakeCreateMessageRequest());
  });

  setUp(() {
    mockClient = MockAnthropicClient();
    service = NarrationService(apiKey: 'test-key', client: mockClient);
  });

  group('NarrationService', () {
    test('generates annotated narration script via forced tool use', () async {
      when(
        () => mockClient.createMessage(request: any(named: 'request')),
      ).thenAnswer(
        (_) async => _narrationToolUseMessage({
          'annotated_script':
              '[CONCEPT:spaced-rep]Spaced repetition[/CONCEPT] is a learning '
              'technique that leverages the [CONCEPT:forgetting-curve]forgetting '
              'curve[/CONCEPT] to optimize review timing.',
        }),
      );

      final result = await service.generateNarrationScript(
        concepts: [
          const ConceptSummary(id: 'spaced-rep', name: 'Spaced Repetition'),
          const ConceptSummary(
            id: 'forgetting-curve',
            name: 'Forgetting Curve',
          ),
        ],
        relationships: [
          const RelationshipSummary(
            fromName: 'Spaced Repetition',
            toName: 'Forgetting Curve',
            label: 'leverages',
          ),
        ],
      );

      expect(result, contains('[CONCEPT:spaced-rep]'));
      expect(result, contains('[CONCEPT:forgetting-curve]'));
      expect(result, contains('[/CONCEPT]'));
    });

    test('passes concept names and relationships in prompt', () async {
      CreateMessageRequest? capturedRequest;

      when(
        () => mockClient.createMessage(request: any(named: 'request')),
      ).thenAnswer((invocation) async {
        capturedRequest =
            invocation.namedArguments[const Symbol('request')]
                as CreateMessageRequest;
        return _narrationToolUseMessage({
          'annotated_script': '[CONCEPT:a]Alpha[/CONCEPT].',
        });
      });

      await service.generateNarrationScript(
        concepts: [
          const ConceptSummary(id: 'a', name: 'Alpha'),
          const ConceptSummary(id: 'b', name: 'Beta'),
        ],
        relationships: [
          const RelationshipSummary(
            fromName: 'Alpha',
            toName: 'Beta',
            label: 'enables',
          ),
        ],
      );

      expect(capturedRequest, isNotNull);
      // Verify the user message contains concept info.
      final userContent = capturedRequest!.messages.first.content;
      final text = switch (userContent) {
        MessageContentText(:final text) => text,
        _ => '',
      };
      expect(text, contains('Alpha'));
      expect(text, contains('Beta'));
      expect(text, contains('enables'));
    });

    test('throws NarrationException when Claude returns no tool use', () async {
      when(
        () => mockClient.createMessage(request: any(named: 'request')),
      ).thenAnswer(
        (_) async => const Message(
          id: 'msg-no-tool',
          role: MessageRole.assistant,
          stopReason: StopReason.endTurn,
          content: MessageContent.text('Here is a narration...'),
          model: 'claude-sonnet-4-5-20250929',
          type: 'message',
          usage: Usage(inputTokens: 10, outputTokens: 10),
        ),
      );

      expect(
        () => service.generateNarrationScript(
          concepts: [const ConceptSummary(id: 'a', name: 'A')],
          relationships: [],
        ),
        throwsA(isA<NarrationException>()),
      );
    });

    test('handles empty concept list gracefully', () async {
      when(
        () => mockClient.createMessage(request: any(named: 'request')),
      ).thenAnswer(
        (_) async => _narrationToolUseMessage({
          'annotated_script': 'No concepts to narrate.',
        }),
      );

      final result = await service.generateNarrationScript(
        concepts: [],
        relationships: [],
      );

      expect(result, 'No concepts to narrate.');
    });

    test('uses forced tool choice for generate_narration', () async {
      CreateMessageRequest? capturedRequest;

      when(
        () => mockClient.createMessage(request: any(named: 'request')),
      ).thenAnswer((invocation) async {
        capturedRequest =
            invocation.namedArguments[const Symbol('request')]
                as CreateMessageRequest;
        return _narrationToolUseMessage({
          'annotated_script': '[CONCEPT:a]A[/CONCEPT].',
        });
      });

      await service.generateNarrationScript(
        concepts: [const ConceptSummary(id: 'a', name: 'A')],
        relationships: [],
      );

      expect(capturedRequest!.toolChoice?.type, ToolChoiceType.tool);
      expect(capturedRequest!.toolChoice?.name, 'generate_narration');
    });
  });
}
