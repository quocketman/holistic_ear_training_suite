import 'dart:math';
import 'package:flutter/material.dart';
import '../models/hex_grid_cell.dart';
import '../models/enums.dart';
import '../models/level_specs.dart';
import '../models/tone_token_colors.dart';
import '../utils/hex_grid_builder.dart';
import '../widgets/connection_visualizer.dart';
import 'practice_screen.dart';

/// Zoomed-in level card. Shows a large connection visualizer, three phase
/// play buttons, and tier dots. Swipe left/right between in-a-row tiers.
class LevelCardScreen extends StatefulWidget {
  final List<HexGridCell> row;
  final int initialColumn;

  const LevelCardScreen({
    super.key,
    required this.row,
    required this.initialColumn,
  });

  @override
  State<LevelCardScreen> createState() => _LevelCardScreenState();
}

class _LevelCardScreenState extends State<LevelCardScreen> {
  late final PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialColumn;
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.row[_currentPage];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('${cell.displayLabel}  ×${_currentPage + 1}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: hexGridColumns,
              onPageChanged: (page) => setState(() => _currentPage = page),
              itemBuilder: (context, index) {
                return _TierPage(cell: widget.row[index]);
              },
            ),
          ),
          // Tier dots.
          Padding(
            padding: const EdgeInsets.only(bottom: 32, top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(hexGridColumns, (i) {
                final tierCell = widget.row[i];
                final isCurrent = i == _currentPage;
                final hasLevels = tierCell.hasLevels;
                return GestureDetector(
                  onTap: () => _pageController.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: isCurrent ? 12 : 10,
                    height: isCurrent ? 12 : 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCurrent
                          ? Colors.white
                          : hasLevels
                              ? Colors.white24
                              : Colors.white10,
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tier page ────────────────────────────────────────────────────────────────

class _TierPage extends StatelessWidget {
  final HexGridCell cell;
  const _TierPage({required this.cell});

  @override
  Widget build(BuildContext context) {
    if (!cell.hasLevels) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text('Coming soon',
                style: TextStyle(color: Colors.white24, fontSize: 16)),
          ],
        ),
      );
    }

    if (!cell.isUnlocked) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text('Locked',
                style: TextStyle(color: Colors.white24, fontSize: 16)),
          ],
        ),
      );
    }

    final rep = cell.representativeLevel!;
    final mode = rep.preferredMode ?? Mode.major;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Size the flat-top hex to fit, leaving room for buttons below.
        const buttonsHeight = 100.0; // buttons + spacing
        final maxWidth = constraints.maxWidth * 0.85;
        final maxHeight = (constraints.maxHeight - buttonsHeight) * 0.92;
        // Flat-top hex: height = width * sqrt(3)/2 ≈ width * 0.866
        final hexWidth = min(maxWidth, maxHeight / 0.866);
        final hexHeight = hexWidth * 0.866;

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hex container with visualizer inside.
              SizedBox(
                width: hexWidth,
                height: hexHeight,
                child: Stack(
                  children: [
                    CustomPaint(
                      painter: _HexContainerPainter(),
                      child: const SizedBox.expand(),
                    ),
                    // Connection visualizer — padded inside the hex.
                    Positioned(
                      left: hexWidth * 0.18,
                      right: hexWidth * 0.18,
                      top: hexHeight * 0.10,
                      bottom: hexHeight * 0.10,
                      child: ConnectionVisualizer(
                        levelSpecs: rep,
                        mode: mode,
                        showOutlines: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Phase buttons below the hex.
              _PhaseButtons(cell: cell),
            ],
          ),
        );
      },
    );
  }
}

// ── Hex container painter ────────────────────────────────────────────────────

/// Flat-top hex path helper used by both painter and clipper.
Path _flatTopHexPath(Size size, {double inset = 0.98}) {
  final cx = size.width / 2;
  final cy = size.height / 2;
  final r = size.width / 2 * inset;
  final path = Path();
  for (int i = 0; i < 6; i++) {
    // Flat-top: vertex 0 at 0° (right).
    final angle = (60.0 * i) * pi / 180.0;
    final x = cx + r * cos(angle);
    final y = cy + r * sin(angle);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

class _HexContainerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _flatTopHexPath(size);
    canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.05));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlatTopHexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _flatTopHexPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ── Three phase play buttons ─────────────────────────────────────────────────

class _PhaseButtons extends StatelessWidget {
  final HexGridCell cell;
  const _PhaseButtons({required this.cell});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Warm-up: green fill, white outline.
        _PhaseHexButton(
          fillColor: ToneTokenColors.faColor,
          outlineColor: Colors.white,
          label: 'Warm-up',
          locked: false,
          onTap: cell.warmUpLevel != null
              ? () => _play(context, cell.warmUpLevel!)
              : null,
        ),
        // Practice: white fill, blue outline.
        _PhaseHexButton(
          fillColor: Colors.white,
          outlineColor: Colors.lightBlueAccent,
          iconColor: Colors.black87,
          label: 'Practice',
          locked: false,
          onTap: cell.practiceLevel != null
              ? () => _play(context, cell.practiceLevel!)
              : null,
        ),
        // Challenge: black fill, red outline. Locked until practice cleared.
        _PhaseHexButton(
          fillColor: Colors.black,
          outlineColor: Colors.redAccent,
          iconColor: Colors.redAccent,
          label: 'Challenge',
          locked: !cell.practiceCleared,
          onTap: cell.challengeLevel != null && cell.practiceCleared
              ? () => _play(context, cell.challengeLevel!)
              : null,
        ),
      ],
    );
  }

  void _play(BuildContext context, LevelSpecs level) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeScreen(
          levelSpecs: level,
          allLevels: cell.cellLevels,
          currentLevelIndex: cell.cellLevels.indexOf(level),
        ),
      ),
    );
  }
}

class _PhaseHexButton extends StatelessWidget {
  final Color fillColor;
  final Color outlineColor;
  final Color iconColor;
  final String label;
  final bool locked;
  final VoidCallback? onTap;

  const _PhaseHexButton({
    required this.fillColor,
    required this.outlineColor,
    this.iconColor = Colors.white,
    required this.label,
    required this.locked,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CustomPaint(
              painter: _HexButtonPainter(
                fillColor: locked ? Colors.black : fillColor,
                outlineColor: locked ? Colors.white24 : outlineColor,
              ),
              child: Center(
                child: locked
                    ? Icon(Icons.lock_outline,
                        color: Colors.white24, size: 22)
                    : Icon(Icons.play_arrow, color: iconColor, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: locked ? Colors.white24 : Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}

class _HexButtonPainter extends CustomPainter {
  final Color fillColor;
  final Color outlineColor;

  _HexButtonPainter({required this.fillColor, required this.outlineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 * 0.88;

    final path = Path();
    for (int i = 0; i < 6; i++) {
      // Flat-top hex (matches game board tokens).
      final angle = (60.0 * i) * pi / 180.0;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );
  }

  @override
  bool shouldRepaint(covariant _HexButtonPainter old) =>
      old.fillColor != fillColor || old.outlineColor != outlineColor;
}
