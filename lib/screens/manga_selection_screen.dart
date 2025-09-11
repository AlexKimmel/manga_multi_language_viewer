import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:manga_muli_language_viewer/screens/dual_pdf_reader.dart';
import 'package:pdf_render/pdf_render.dart';

class MangaSelectionScreen extends StatefulWidget {
  const MangaSelectionScreen({super.key});

  @override
  State<MangaSelectionScreen> createState() => _MangaSelectionScreenState();
}

class _MangaSelectionScreenState extends State<MangaSelectionScreen> {
  FilePickerResult? topManga;
  FilePickerResult? bottomManga;

  int pageCount = 0;

  Future<int> _getPdfPageCount(String path) async {
    try {
      // Use the pdf_render package to open the PDF and get the page count
      final doc = await PdfDocument.openFile(path);
      final count = doc.pageCount;
      await doc.dispose();
      return count;
    } catch (e) {
      log('Error getting PDF page count: $e');
      return 0;
    }
  }

  Future<FilePickerResult?> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null && result.files.isNotEmpty) {
        // get the number of pages in the PDF and set
        pageCount = await _getPdfPageCount(result.files.first.path!);
        return result;
      }
    } catch (e) {
      log('Error picking file: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Explanation text
            const Text(
              "Multi-Manga-View",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 32),
            ),
            const Text("Select two mangas to view them ontop of each other"),
            const Text(
                "(e.g. Learning Language Manga and Known Language Manga)"),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Button to select front manga
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: MacosIconButton(
                    icon: const Text("Select Top Manga"),
                    onPressed: () async {
                      final result = await _pickFile();
                      if (result != null) {
                        setState(() {
                          topManga = result;
                        });
                      }
                    },
                  ),
                ),
                // Button to select back manga
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: MacosIconButton(
                    icon: const Text("Select Bottom Manga"),
                    onPressed: () async {
                      final result = await _pickFile();
                      if (result != null) {
                        setState(() {
                          bottomManga = result;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            // Text that displays the names of the files
            if (topManga != null)
              Text("Top File: ${topManga!.files.first.name}"),

            if (bottomManga != null)
              Text("Top File: ${bottomManga!.files.first.name}"),

            // Button to read manga
            if (topManga != null && bottomManga != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: MacosIconButton(
                  icon: const Text("Read!"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => DualPdfReader(
                          pdfA: topManga!.paths.first.toString(),
                          pdfB: bottomManga!.paths.first.toString(),
                          pageCount: 100,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
