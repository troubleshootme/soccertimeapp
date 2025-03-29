import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/app_themes.dart';

class PdfPreviewScreen extends StatefulWidget {
  final File pdfFile;
  final String title;

  const PdfPreviewScreen({
    Key? key, 
    required this.pdfFile,
    required this.title,
  }) : super(key: key);

  @override
  _PdfPreviewScreenState createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isLoading = true;
  PDFViewController? _pdfViewController;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppThemes.darkBackground : AppThemes.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(Icons.share),
            tooltip: 'Share PDF',
            onPressed: _sharePdf,
          ),
        ],
      ),
      body: Stack(
        children: [
          PDFView(
            filePath: widget.pdfFile.path,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            pageSnap: true,
            defaultPage: _currentPage,
            fitPolicy: FitPolicy.BOTH,
            preventLinkNavigation: false,
            onRender: (_pages) {
              setState(() {
                _totalPages = _pages!;
                _isLoading = false;
              });
            },
            onError: (error) {
              setState(() {
                _isLoading = false;
              });
              print('Error loading PDF: $error');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error loading PDF: $error'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            onPageError: (page, error) {
              print('Error loading page $page: $error');
            },
            onViewCreated: (PDFViewController pdfViewController) {
              setState(() {
                _pdfViewController = pdfViewController;
              });
            },
            onPageChanged: (int? page, int? total) {
              if (page != null) {
                setState(() {
                  _currentPage = page;
                });
              }
            },
          ),
          _isLoading
              ? Center(
                  child: CircularProgressIndicator(
                    color: isDark 
                        ? AppThemes.darkSecondaryBlue 
                        : AppThemes.lightSecondaryBlue,
                  ),
                )
              : Container(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(isDark),
    );
  }

  Widget _buildBottomNavigationBar(bool isDark) {
    if (_totalPages <= 1) {
      return Container(height: 0);
    }

    return Container(
      height: 56,
      color: isDark ? AppThemes.darkPrimaryBlue : AppThemes.lightPrimaryBlue,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back),
            color: Colors.white,
            disabledColor: Colors.white38,
            onPressed: _currentPage > 0
                ? () {
                    _pdfViewController?.setPage(_currentPage - 1);
                  }
                : null,
          ),
          Text(
            'Page ${_currentPage + 1} of $_totalPages',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          IconButton(
            icon: Icon(Icons.arrow_forward),
            color: Colors.white,
            disabledColor: Colors.white38,
            onPressed: _currentPage < _totalPages - 1
                ? () {
                    _pdfViewController?.setPage(_currentPage + 1);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _sharePdf() async {
    try {
      await Share.shareXFiles(
        [XFile(widget.pdfFile.path)], 
        text: 'Match Log PDF',
      );
    } catch (e) {
      print('Error sharing PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
} 