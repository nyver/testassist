import 'package:flutter_test/flutter_test.dart';
import 'package:test_assistant/features/ocr/domain/question_parser.dart';
import 'package:test_assistant/features/questions/domain/models.dart';

typedef _Case = ({
  String name,
  String text,
  String question,
  List<(String, String)> options,
});

void main() {
  const parser = QuestionParser();

  List<(String, String)> pairs(ParsedQuestion p) => [
    for (final o in p.options) (o.id, o.text),
  ];

  group('the specification scenarios', () {
    final cases = <_Case>[
      (
        name: 'lettered options',
        text: 'Which protocol encrypts HTTP?\nA. FTP\nB. HTTPS\nC. SMTP\nD. Telnet',
        question: 'Which protocol encrypts HTTP?',
        options: [('A', 'FTP'), ('B', 'HTTPS'), ('C', 'SMTP'), ('D', 'Telnet')],
      ),
      (
        name: 'Cyrillic options with parentheses',
        text: 'Какой протокол надёжнее?\nа) TCP\nб) UDP\nв) ICMP',
        question: 'Какой протокол надёжнее?',
        options: [('А', 'TCP'), ('Б', 'UDP'), ('В', 'ICMP')],
      ),
      (
        name: 'numbered options',
        text: 'Pick a color\n1. Red\n2. Green\n3. Blue',
        question: 'Pick a color',
        options: [('1', 'Red'), ('2', 'Green'), ('3', 'Blue')],
      ),
      (
        name: 'question number with lettered options',
        text: '5. What is 2+2?\nA) 3\nB) 4',
        question: 'What is 2+2?',
        options: [('A', '3'), ('B', '4')],
      ),
      (
        name: 'multi-line option',
        text: 'Q?\nA. first\nB. second line\ncontinues here\nC. third',
        question: 'Q?',
        options: [
          ('A', 'first'),
          ('B', 'second line continues here'),
          ('C', 'third'),
        ],
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        final parsed = parser.parse(c.text);
        expect(parsed.question, c.question);
        expect(pairs(parsed), c.options);
        expect(parsed.isLowQuality, isFalse);
      });
    }
  });

  group('marker forms', () {
    test('parentheses around the label', () {
      final p = parser.parse('Q\n(A) one\n(B) two');
      expect(pairs(p), [('A', 'one'), ('B', 'two')]);
    });

    test('lower-case Latin labels become upper case', () {
      final p = parser.parse('Q\na) one\nb) two\nc) three');
      expect(p.options.map((o) => o.id), ['A', 'B', 'C']);
    });

    test('numbers with a closing parenthesis', () {
      final p = parser.parse('Q\n1) one\n2) two');
      expect(pairs(p), [('1', 'one'), ('2', 'two')]);
    });

    test('numbers in parentheses', () {
      final p = parser.parse('Q\n(1) one\n(2) two');
      expect(pairs(p), [('1', 'one'), ('2', 'two')]);
    });

    test('no space after the marker', () {
      final p = parser.parse('Q\nA.one\nB)two');
      expect(pairs(p), [('A', 'one'), ('B', 'two')]);
    });

    test('a two-digit number', () {
      final p = parser.parse('Q\n9. nine\n10. ten\n11. eleven');
      expect(p.options.map((o) => o.id), ['9', '10', '11']);
    });

    test('upper-case Cyrillic labels', () {
      final p = parser.parse('Вопрос\nА. один\nБ. два');
      expect(pairs(p), [('А', 'один'), ('Б', 'два')]);
    });

    test('the traditional Cyrillic enumeration that skips Ё, Й, Ъ, Ы, Ь', () {
      final p = parser.parse('Q\nе) e\nж) zh\nз) z\nи) i\nк) k');
      expect(p.options.map((o) => o.id), ['Е', 'Ж', 'З', 'И', 'К']);
    });

    test('an option marker with the text on the next line', () {
      final p = parser.parse('Q\nA.\nlonger text\nB. two');
      expect(pairs(p), [('A', 'longer text'), ('B', 'two')]);
    });

    test('Windows line endings and blank lines are ignored', () {
      final p = parser.parse('Q?\r\n\r\nA. one\r\n\r\nB. two\r\n');
      expect(p.question, 'Q?');
      expect(pairs(p), [('A', 'one'), ('B', 'two')]);
    });

    test('extra whitespace around lines is trimmed', () {
      final p = parser.parse('   Q?   \n   A.   one   \n B.  two ');
      expect(p.question, 'Q?');
      expect(pairs(p), [('A', 'one'), ('B', 'two')]);
    });
  });

  group('the question', () {
    test('several lines are joined with spaces', () {
      final p = parser.parse(
        'Which of the following\nprotocols encrypts\ntraffic?\nA. x\nB. y',
      );
      expect(p.question, 'Which of the following protocols encrypts traffic?');
    });

    test('a leading question number is kept for numbered options', () {
      final p = parser.parse('Pick one\n1. a\n2. b');
      expect(p.question, 'Pick one');
    });

    test('a question number in parentheses style is dropped for letters', () {
      final p = parser.parse('12) Name the capital\nA. Paris\nB. Rome');
      expect(p.question, 'Name the capital');
    });

    test(
      'numbered statements before lettered options stay in the question',
      () {
        final p = parser.parse(
          'Which statements are true?\n1. Water is wet\n2. Fire is cold\nA. 1 only\nB. 2 only\nC. both\nD. neither',
        );
        expect(p.options.map((o) => o.id), ['A', 'B', 'C', 'D']);
        expect(p.question, contains('Water is wet'));
        expect(p.question, contains('Fire is cold'));
      },
    );

    test('a decimal is not an option marker', () {
      final p = parser.parse('Q?\n2.5 metres long\nA. one\nB. two');
      expect(p.question, 'Q? 2.5 metres long');
      expect(p.options, hasLength(2));
    });

    test('a numbered line inside lettered options is a continuation', () {
      final p = parser.parse('Q\nA. items:\n1. first\nB. other');
      expect(pairs(p), [('A', 'items: 1. first'), ('B', 'other')]);
    });
  });

  group('low-quality recognition', () {
    test('empty text', () {
      final p = parser.parse('');
      expect(p.isLowQuality, isTrue);
      expect(p.warnings, contains(ParseWarning.noText));
      expect(p.question, isEmpty);
      expect(p.options, isEmpty);
    });

    test('whitespace only', () {
      expect(parser.parse('  \n \r\n').warnings, contains(ParseWarning.noText));
    });

    test('a question without options', () {
      final p = parser.parse('Just some sentence without answers.');
      expect(p.question, 'Just some sentence without answers.');
      expect(p.options, isEmpty);
      expect(p.warnings, contains(ParseWarning.tooFewOptions));
      expect(p.isLowQuality, isTrue);
    });

    test('a single option is still found and reported', () {
      final p = parser.parse('What is 2+2?\nA. four');
      expect(p.question, 'What is 2+2?');
      expect(pairs(p), [('A', 'four')]);
      expect(p.warnings, contains(ParseWarning.tooFewOptions));
      expect(p.isLowQuality, isTrue);
    });

    test('options without a question', () {
      final p = parser.parse('A. one\nB. two');
      expect(p.question, isEmpty);
      expect(p.warnings, contains(ParseWarning.emptyQuestion));
      expect(p.isLowQuality, isTrue);
    });

    test('a lone number is not treated as an option', () {
      final p = parser.parse('5. What is 2+2?');
      expect(p.options, isEmpty);
      expect(p.question, contains('What is 2+2?'));
    });

    test('non-consecutive lettered markers still give options', () {
      final p = parser.parse('Q?\nA. one\nC. three');
      expect(p.options.map((o) => o.id), ['A', 'C']);
      expect(p.isLowQuality, isFalse);
    });

    test('duplicate ids are reported', () {
      final p = parser.parse('Q?\nA. one\nB. two\nB. dup\nC. three');
      expect(p.warnings, contains(ParseWarning.duplicateIds));
    });
  });

  test('parsing is deterministic', () {
    const text = 'Q?\nA. one\nB. two\nC. three';
    final first = parser.parse(text);
    final second = parser.parse(text);
    expect(first.question, second.question);
    expect(first.options, second.options);
  });

  test('option ids are usable by the request validation', () {
    final p = parser.parse('Q?\nA. one\nB. two');
    expect(DraftValidation.of(p.question, p.options).canSend, isTrue);
  });
}
