import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import '../models/match_log_entry.dart';
import '../models/session.dart';
import 'dart:math' as math;

class PdfService {
  static final PdfService _instance = PdfService._internal();
  factory PdfService() => _instance;
  PdfService._internal();

  // Cache for icons
  final Map<String, pw.MemoryImage> _iconCache = {};

  // Format the timestamp in a friendly format (Month Day, Year)
  Map<String, String> _formatTimestampParts(String timestamp) {
    try {
      final DateTime dateTime = DateTime.parse(timestamp);
      final DateFormat dateFormatter = DateFormat('MMMM d, yyyy');
      final DateFormat timeFormatter = DateFormat('h:mm a');
      return {
        'date': dateFormatter.format(dateTime),
        'time': timeFormatter.format(dateTime)
      };
    } catch (e) {
      final now = DateTime.now();
      return {
        'date': DateFormat('MMMM d, yyyy').format(now),
        'time': DateFormat('h:mm a').format(now)
      };
    }
  }

  // Generate PDF from match log entries
  Future<File> generateMatchLogPdf({
    required List<MatchLogEntry> entries,
    required Session session,
    required bool isDarkTheme,
  }) async {
    // Create a PDF document
    final pdf = pw.Document();
    
    // Define printer-friendly colors (black & white with minimal accent colors)
    final headerBorderColor = PdfColors.grey600;
    final textColor = PdfColors.black;
    final headerTextColor = PdfColors.black;
    final iconColor = PdfColors.black;
    
    // Define event types with printer-friendly border colors
    final matchEventBorderColor = PdfColors.lightBlue;
    // Use the emerald color from match_log_screen.dart (0xFF26C485)
    final playerEnterBorderColor = PdfColor(0x26/255, 0xC4/255, 0x85/255);
    final goalBorderColor = PdfColors.orange800;
    // Use the softRed light theme color from match_log_screen.dart (0xFFE57373)
    final playerExitBorderColor = PdfColor(0xE5/255, 0x73/255, 0x73/255);
    final defaultBorderColor = PdfColors.grey700;
    
    // Get timestamp parts
    final timestampParts = _formatTimestampParts(DateTime.now().toString());
    
    // Pre-load all icons - using actual png files from assets
    final soccerballIcon = await _createSoccerBallFromPng();
    final whistleIcon = await _createWhistleFromSvg();
    final playerEnterIcon = await _createArrowRightIcon(Colors.black);
    final playerExitIcon = await _createArrowLeftIcon(Colors.black);
    final defaultIcon = await _createDefaultIcon(Colors.black);
    
    // Add pages to the PDF
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                  color: headerBorderColor,
                  width: 0.5,
                ),
              ),
            ),
            child: pw.Column(
              children: [
                // Top row: Team name & score on left, date & time on right
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    // Left side: Team name and score
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          session.sessionName,
                          style: pw.TextStyle(
                            color: headerTextColor,
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '${session.teamGoals} - ${session.opponentGoals}',
                          style: pw.TextStyle(
                            color: headerTextColor,
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    // Right side: Date and time
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          timestampParts['date']!,
                          style: pw.TextStyle(
                            color: headerTextColor,
                            fontSize: 12,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          timestampParts['time']!,
                          style: pw.TextStyle(
                            color: headerTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Second row: Centered title
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'Match Report',
                    style: pw.TextStyle(
                      color: headerTextColor, 
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            // Content with border
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: headerBorderColor,
                  width: 1,
                ),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                children: entries.map((entry) {
                  if (entry.details.toLowerCase().contains('reset')) {
                    return pw.Container(); // Skip reset entries
                  }
                  
                  // Determine entry type
                  final isGoal = entry.details.toLowerCase().contains('goal') || 
                               entry.entryType?.toLowerCase() == 'goal';
                  final isWhistleEntry = entry.entryType?.toLowerCase() == 'match_start' ||
                                      entry.entryType?.toLowerCase() == 'period_transition' ||
                                      entry.entryType?.toLowerCase() == 'match_end';
                  final isMatchStart = entry.details.toLowerCase().contains('match started') ||
                                     entry.entryType?.toLowerCase() == 'match_start';
                  final isPlayerEnter = entry.details.toLowerCase().contains('entered the game');
                  final isPlayerExit = entry.details.toLowerCase().contains('left the game');
                  
                  // Determine border color and icon
                  PdfColor borderColor;
                  pw.MemoryImage icon;
                  
                  if (isGoal) {
                    borderColor = goalBorderColor;
                    icon = soccerballIcon;
                  } else if (isWhistleEntry || isMatchStart) {
                    borderColor = matchEventBorderColor;
                    icon = whistleIcon;
                  } else if (isPlayerEnter) {
                    borderColor = playerEnterBorderColor;
                    icon = playerEnterIcon;
                  } else if (isPlayerExit) {
                    borderColor = playerExitBorderColor;
                    icon = playerExitIcon;
                  } else {
                    borderColor = defaultBorderColor;
                    icon = defaultIcon;
                  }
                  
                  return pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 8),
                    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        left: pw.BorderSide(
                          color: borderColor, 
                          width: 4,
                        ),
                      ),
                      color: PdfColors.white,
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        // Icon and details section
                        pw.Expanded(
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              // Icon
                              pw.Container(
                                width: 24,
                                height: 24,
                                child: pw.Image(icon, width: 20, height: 20),
                              ),
                              pw.SizedBox(width: 8),
                              // Event details
                              pw.Expanded(
                                child: pw.Text(
                                  entry.details,
                                  style: pw.TextStyle(
                                    color: textColor,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Time section - right-aligned column with match time
                        pw.Container(
                          width: 80,
                          height: 22,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(
                              color: borderColor,
                              width: 1,
                            ),
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            entry.matchTime,
                            style: pw.TextStyle(
                              color: textColor,
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ];
        },
        footer: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                  color: headerBorderColor,
                  width: 0.5,
                ),
              ),
            ),
            child: pw.Row(
              children: [
                // Left aligned team name
                pw.Expanded(
                  flex: 1,
                  child: pw.Text(
                    session.sessionName,
                    style: pw.TextStyle(
                      color: PdfColors.black,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                // Center aligned app info
                pw.Expanded(
                  flex: 1,
                  child: pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'SoccerTimeApp',
                          style: pw.TextStyle(
                            color: PdfColors.black,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'www.soccertimeapp.com',
                          style: pw.TextStyle(
                            color: PdfColors.black,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Right aligned page numbers
                pw.Expanded(
                  flex: 1,
                  child: pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'Page ${context.pageNumber} of ${context.pagesCount}',
                      style: pw.TextStyle(
                        color: PdfColors.black,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    
    // Get the temp directory
    final tempDir = await getTemporaryDirectory();
    final tempPath = tempDir.path;
    final filePath = '$tempPath/match_log.pdf';
    
    // Save the PDF to a file
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    
    return file;
  }
  
  // Helper method to load an image asset as a MemoryImage for the PDF
  Future<pw.MemoryImage> _loadImageAsset(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      print('Error loading asset $assetPath: $e');
      // Return a fallback icon if loading fails
      return await _createDefaultIcon(Colors.black);
    }
  }
  
  // Create a soccer ball icon (fallback if asset loading fails)
  Future<pw.MemoryImage> _createSoccerballIcon(Color color) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const double size = 24;
    
    // Draw a filled circle for the soccer ball
    final Paint circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(size/2, size/2),
      size/2 - 2,
      circlePaint,
    );
    
    // Draw pentagon pattern on top with white
    final Paint patternPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    // Add a classic soccer ball pentagon pattern
    // Draw a pentagon in the center
    const pentagonPoints = 5;
    const pentagonRadius = 5.0;
    const centerX = size / 2;
    const centerY = size / 2;
    
    List<Offset> pentPoints = [];
    for (var i = 0; i < pentagonPoints; i++) {
      final angle = (i * 2 * math.pi / pentagonPoints) - math.pi / 2;
      final x = centerX + pentagonRadius * math.cos(angle);
      final y = centerY + pentagonRadius * math.sin(angle);
      pentPoints.add(Offset(x, y));
    }
    
    // Draw the pentagon
    for (var i = 0; i < pentagonPoints; i++) {
      canvas.drawLine(
        pentPoints[i], 
        pentPoints[(i + 1) % pentagonPoints],
        patternPaint,
      );
    }
    
    // Add some connecting lines for the hexagon pattern
    for (var i = 0; i < pentagonPoints; i++) {
      final angle = ((i + 0.5) * 2 * math.pi / pentagonPoints) - math.pi / 2;
      final x = centerX + (size/2 - 2) * math.cos(angle);
      final y = centerY + (size/2 - 2) * math.sin(angle);
      
      canvas.drawLine(
        pentPoints[i],
        Offset(x, y),
        patternPaint,
      );
    }
    
    final ui.Image image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return pw.MemoryImage(Uint8List(0));
    }
    
    return pw.MemoryImage(byteData.buffer.asUint8List());
  }
  
  // Create a whistle icon (fallback if asset loading fails)
  Future<pw.MemoryImage> _createWhistleIcon(Color color) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const double size = 24;
    
    // Use fill style for better visibility at small sizes
    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final Paint whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    // Draw a simplified but recognizable whistle shape
    // Main whistle body
    final Path whistlePath = Path();
    whistlePath.moveTo(5, 8);    // Top left
    whistlePath.lineTo(14, 8);   // Top edge
    whistlePath.lineTo(19, 12);  // Top right curve
    whistlePath.lineTo(17, 16);  // Bottom right curve
    whistlePath.lineTo(5, 16);   // Bottom edge
    whistlePath.close();         // Close the path
    
    // The lanyard/attachment part of the whistle
    final Path attachmentPath = Path();
    attachmentPath.moveTo(14, 8);   // Connection point to main body
    attachmentPath.lineTo(18, 4);   // Top right
    attachmentPath.lineTo(13, 4);   // Top left
    attachmentPath.close();         // Close the path
    
    // Draw the filled shapes
    canvas.drawPath(whistlePath, fillPaint);
    canvas.drawPath(attachmentPath, fillPaint);
    
    // Add a small white circle for the whistle hole
    canvas.drawCircle(
      Offset(8, 12),
      2,
      whitePaint,
    );
    
    final ui.Image image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return pw.MemoryImage(Uint8List(0));
    }
    
    return pw.MemoryImage(byteData.buffer.asUint8List());
  }
  
  // Create an arrow pointing right icon (player entering)
  Future<pw.MemoryImage> _createArrowRightIcon(Color color) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const double size = 24;
    
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    // Draw arrow shaft
    canvas.drawLine(
      Offset(4, size/2),
      Offset(size-4, size/2),
      paint,
    );
    
    // Draw arrowhead
    canvas.drawLine(
      Offset(size-8, size/2-4),
      Offset(size-4, size/2),
      paint,
    );
    
    canvas.drawLine(
      Offset(size-8, size/2+4),
      Offset(size-4, size/2),
      paint,
    );
    
    final ui.Image image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return pw.MemoryImage(Uint8List(0));
    }
    
    return pw.MemoryImage(byteData.buffer.asUint8List());
  }
  
  // Create an arrow pointing left icon (player exiting)
  Future<pw.MemoryImage> _createArrowLeftIcon(Color color) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const double size = 24;
    
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    // Draw arrow shaft
    canvas.drawLine(
      Offset(size-4, size/2),
      Offset(4, size/2),
      paint,
    );
    
    // Draw arrowhead
    canvas.drawLine(
      Offset(8, size/2-4),
      Offset(4, size/2),
      paint,
    );
    
    canvas.drawLine(
      Offset(8, size/2+4),
      Offset(4, size/2),
      paint,
    );
    
    final ui.Image image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return pw.MemoryImage(Uint8List(0));
    }
    
    return pw.MemoryImage(byteData.buffer.asUint8List());
  }
  
  // Create a default icon (plus sign)
  Future<pw.MemoryImage> _createDefaultIcon(Color color) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const double size = 24;
    
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    // Draw a plus sign
    canvas.drawLine(
      Offset(4, size/2),
      Offset(size-4, size/2),
      paint,
    );
    
    canvas.drawLine(
      Offset(size/2, 4),
      Offset(size/2, size-4),
      paint,
    );
    
    final ui.Image image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return pw.MemoryImage(Uint8List(0));
    }
    
    return pw.MemoryImage(byteData.buffer.asUint8List());
  }

  // Convert an SVG asset to a PDF-compatible MemoryImage
  Future<pw.MemoryImage> _createWhistleFromSvg() async {
    try {
      // First try to use the PNG file if available
      try {
        final data = await rootBundle.load('assets/images/whistle_icon.png');
        return pw.MemoryImage(data.buffer.asUint8List());
      } catch (e) {
        // If PNG fails, try loading the SVG and converting it
        print('PNG failed, falling back to drawing: $e');
      }
      
      // If PNG loading fails, use the manual drawing as fallback
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      const double size = 24;
      
      final Paint fillPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;
      
      final Paint whitePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      
      // Draw a simplified whistle shape
      final Path whistlePath = Path();
      whistlePath.moveTo(5, 8);    // Top left
      whistlePath.lineTo(14, 8);   // Top edge
      whistlePath.lineTo(19, 12);  // Top right curve
      whistlePath.lineTo(17, 16);  // Bottom right curve
      whistlePath.lineTo(5, 16);   // Bottom edge
      whistlePath.close();         // Close the path
      
      // The triangular attachment
      final Path attachmentPath = Path();
      attachmentPath.moveTo(14, 8);   // Connection point to main body
      attachmentPath.lineTo(18, 4);   // Top right
      attachmentPath.lineTo(13, 4);   // Top left
      attachmentPath.close();         // Close the path
      
      // Draw the filled shapes
      canvas.drawPath(whistlePath, fillPaint);
      canvas.drawPath(attachmentPath, fillPaint);
      
      // Add a small white circle for the whistle hole
      canvas.drawCircle(
        Offset(8, 12),
        2,
        whitePaint,
      );
      
      final ui.Image image = await recorder.endRecording().toImage(
        size.toInt(),
        size.toInt(),
      );
      
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Failed to convert to PNG');
      }
      
      return pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (e) {
      print('Failed to create whistle icon: $e');
      return await _createDefaultIcon(Colors.black);
    }
  }
  
  // Convert a PNG asset to a PDF-compatible MemoryImage
  Future<pw.MemoryImage> _createSoccerBallFromPng() async {
    try {
      // Try to load the PNG file directly
      try {
        final data = await rootBundle.load('assets/images/soccerball_icon.png');
        return pw.MemoryImage(data.buffer.asUint8List());
      } catch (e) {
        print('PNG loading failed, falling back to drawing: $e');
      }
      
      // If PNG loading fails, create a soccer ball drawing as fallback
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      const double size = 24;
      
      // Draw a filled circle for the soccer ball
      final Paint circlePaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(size/2, size/2),
        size/2 - 2,
        circlePaint,
      );
      
      // Draw pentagon pattern on top with white
      final Paint patternPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      
      // Draw a pentagon in the center
      const pentagonPoints = 5;
      const pentagonRadius = 5.0;
      const centerX = size / 2;
      const centerY = size / 2;
      
      List<Offset> pentPoints = [];
      for (var i = 0; i < pentagonPoints; i++) {
        final angle = (i * 2 * math.pi / pentagonPoints) - math.pi / 2;
        final x = centerX + pentagonRadius * math.cos(angle);
        final y = centerY + pentagonRadius * math.sin(angle);
        pentPoints.add(Offset(x, y));
      }
      
      // Draw the pentagon
      for (var i = 0; i < pentagonPoints; i++) {
        canvas.drawLine(
          pentPoints[i], 
          pentPoints[(i + 1) % pentagonPoints],
          patternPaint,
        );
      }
      
      // Add some connecting lines for the hexagon pattern
      for (var i = 0; i < pentagonPoints; i++) {
        final angle = ((i + 0.5) * 2 * math.pi / pentagonPoints) - math.pi / 2;
        final x = centerX + (size/2 - 2) * math.cos(angle);
        final y = centerY + (size/2 - 2) * math.sin(angle);
        
        canvas.drawLine(
          pentPoints[i],
          Offset(x, y),
          patternPaint,
        );
      }
      
      final ui.Image image = await recorder.endRecording().toImage(
        size.toInt(),
        size.toInt(),
      );
      
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Failed to convert to PNG');
      }
      
      return pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (e) {
      print('Failed to create soccer ball icon: $e');
      return await _createDefaultIcon(Colors.black);
    }
  }
} 