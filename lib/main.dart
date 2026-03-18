import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:csv/csv.dart';

void main() {
  runApp(const MyApp());
}

// Class representing one word and its data
class Word {
  final String text;
  final String audioPath;
  final List<int> syllableLengths;
  final int stressedIndex;
  final List<String> syllables;

  Word(this.text, this.audioPath, this.syllableLengths, this.stressedIndex,
      this.syllables);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Word> words = [];
  int currentIndex = 0;
  int activeSyllableIndex = -1;
  bool isPlaying = false;

  late final AudioPlayer audioPlayer;

  String statusMessage = '';
  bool showStatus = false;

  @override
  void initState() {
    super.initState();

    // Initialize audio player
    audioPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);

    // Android-specific audio context to fix release mode issues
    if (Platform.isAndroid) {
      audioPlayer.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
    }

    loadCSV();
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    setState(() {
      statusMessage = message;
      showStatus = true;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => showStatus = false);
      }
    });
  }

  // Simple syllable breakdown heuristic
  List<String> breakIntoSyllables(String word, int syllableCount) {
    // This is a simple approximation - ideally you'd have syllables in CSV
    if (syllableCount <= 1) return [word];

    // Try to split roughly evenly
    List<String> result = [];
    int charsPerSyllable = (word.length / syllableCount).ceil();

    for (int i = 0; i < syllableCount; i++) {
      int start = i * charsPerSyllable;
      int end = (i + 1) * charsPerSyllable;
      if (start >= word.length) break;
      if (end > word.length) end = word.length;
      result.add(word.substring(start, end));
    }

    return result;
  }

  // Load CSV file from assets
  Future<void> loadCSV() async {
    try {
      final rawData = await rootBundle.loadString('assets/words.csv');
      final csvData = const CsvToListConverter().convert(rawData, eol: '\n');

      List<Word> loadedWords = [];

      for (int i = 1; i < csvData.length; i++) {
        final row = csvData[i];
        if (row.length < 4) continue;

        // Your CSV format: word, syllables(count), syllable_lengths_ms, stressed_index, syllables
        final text = row[0].toString().trim();
        final syllableCount = int.tryParse(row[1].toString()) ?? 1;

        // Parse syllable durations from column 2
        List<int> syllableLengths = row[2]
            .toString()
            .replaceAll(RegExp(r'[\[\]]'), '')
            .split(',')
            .where((e) => e.trim().isNotEmpty)
            .map((e) => int.tryParse(e.trim()) ?? 100)
            .toList();

        if (syllableLengths.isEmpty) {
          syllableLengths = [100];
        }

        int stressedIndex = int.tryParse(row[3].toString()) ?? 0;
        if (stressedIndex < 0 || stressedIndex >= syllableLengths.length) {
          stressedIndex = 0;
        }

        final audioPath =
            'audio/${text.toLowerCase().replaceAll(RegExp(r'[()]'), '')}.mp3';

        // Use syllable breakdown from CSV column 4 if available, otherwise auto-generate
        List<String> syllables =
            (row.length > 4 && row[4].toString().trim().isNotEmpty)
                ? row[4].toString().trim().split('-')
                : breakIntoSyllables(text, syllableCount);

        loadedWords.add(
          Word(text, audioPath, syllableLengths, stressedIndex, syllables),
        );
      }

      setState(() {
        words = loadedWords;
      });

      showMessage('Loaded ${loadedWords.length} words');
    } catch (e) {
      showMessage('CSV Error: $e');
    }
  }

  // Play audio + rhythmic haptics
  Future<void> playWord(Word word) async {
    if (isPlaying) return; // Prevent multiple simultaneous plays

    setState(() {
      isPlaying = true;
      activeSyllableIndex = -1;
    });

    showMessage('Playing ${word.text}');

    // Android-safe audio playback
    try {
      await audioPlayer.setSourceAsset(word.audioPath);
      await audioPlayer.resume();
    } catch (e) {
      showMessage('Audio error: $e');
      setState(() {
        isPlaying = false;
      });
      return;
    }

    final bool? hasVibrator = await Vibration.hasVibrator();

    // Small delay to sync vibration with audio start
    await Future.delayed(const Duration(milliseconds: 80));

    // Rhythmic syllable loop
    for (int i = 0; i < word.syllableLengths.length; i++) {
      if (!isPlaying) break; // Allow interruption

      setState(() {
        activeSyllableIndex = i;
      });

      final duration = word.syllableLengths[i];

      if (i == word.stressedIndex) {
        // STRONG stress - use heavy impact for better distinction
        if (hasVibrator == true) {
          await Vibration.vibrate(
              duration: duration, amplitude: 255); // Max amplitude
        } else {
          HapticFeedback.heavyImpact(); // Changed from mediumImpact
        }
      } else {
        // LIGHT unstressed tap
        HapticFeedback
            .selectionClick(); // Changed from lightImpact - even lighter
      }

      await Future.delayed(Duration(milliseconds: duration));
    }

    setState(() {
      activeSyllableIndex = -1;
      isPlaying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final currentWord = words[currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Word Vibration App'),
        backgroundColor: Colors.blue[700],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showStatus)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),

            // Main word display
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                currentWord.text,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Syllable breakdown with visual stress indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: List.generate(currentWord.syllables.length, (index) {
                  final isStressed = index == currentWord.stressedIndex;
                  final isActive = index == activeSyllableIndex;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.orange[400]
                          : (isStressed ? Colors.red[100] : Colors.grey[200]),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            isStressed ? Colors.red[700]! : Colors.grey[400]!,
                        width: isStressed ? 3 : 1,
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: Colors.orange.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: Text(
                      currentWord.syllables[index],
                      style: TextStyle(
                        fontSize: isActive ? 22 : 18,
                        fontWeight:
                            isStressed ? FontWeight.bold : FontWeight.normal,
                        color: isActive ? Colors.white : Colors.black87,
                      ),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 40),

            // Replay button
            ElevatedButton.icon(
              onPressed: isPlaying ? null : () => playWord(currentWord),
              icon: Icon(isPlaying ? Icons.hourglass_empty : Icons.replay),
              label: Text(isPlaying ? 'Playing...' : 'Play Word'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'Word ${currentIndex + 1} of ${words.length}',
              style: TextStyle(color: Colors.grey[600]),
            ),

            const SizedBox(height: 40),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: currentIndex > 0
                      ? () => setState(() => currentIndex--)
                      : null,
                  child: const Text('Previous'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: currentIndex < words.length - 1
                      ? () => setState(() => currentIndex++)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
