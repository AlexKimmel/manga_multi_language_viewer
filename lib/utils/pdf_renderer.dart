import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf_render/pdf_render.dart';

Future<Widget> buildPdfPageRawImage({
  required String pathOrAsset,
  required int pageNumber, // 1-based
}) async {
  final doc = pathOrAsset.startsWith('assets/')
      ? await PdfDocument.openAsset(pathOrAsset)
      : await PdfDocument.openFile(pathOrAsset);

  final page = await doc.getPage(pageNumber);
  final pageImage = await page.render();

  // Make a ui.Image and show it with RawImage
  await pageImage.createImageIfNotAvailable();
  final ui.Image? uiImg = pageImage.imageIfAvailable;

  doc.dispose(); // <— dispose the document when you’re done

  if (uiImg == null) {
    // fall back if image isn’t ready
    return const SizedBox.shrink();
  }
  return RawImage(image: uiImg, fit: BoxFit.contain);
}

/// Rasterize a single PDF page to bytes (PNG) you can display with Image.memory.
Future<Uint8List> renderPdfPageBytes({
  required String pdfPathOrAssetOrUrl,
  required int pageNumber, // 1-based index
  int? targetWidth, // pick either width or height to control quality
  int? targetHeight,
}) async {
  late final PdfDocument doc;
  if (pdfPathOrAssetOrUrl.startsWith('http')) {
    // For a URL: download bytes yourself (http) then open with openData
    // (omitted for brevity). If you already have bytes, use PdfDocument.openData(bytes).
    throw UnimplementedError('Download the PDF and call openData(bytes)');
  } else if (pdfPathOrAssetOrUrl.startsWith('assets/')) {
    doc = await PdfDocument.openAsset(pdfPathOrAssetOrUrl);
  } else {
    doc = await PdfDocument.openFile(pdfPathOrAssetOrUrl);
  }

  final page = await doc.getPage(pageNumber);
  final pageImage = await page.render(
    width: targetWidth,
    height: targetHeight,
    // You can also set 'fullWidth/fullHeight' if you know the page’s pixel size you want.
    // backgroundColor: '#FFFFFFFF', // optional
  );
  // await page.close();
  // await doc.close();
  return pageImage.pixels;
}

/// Convenience: produce an Image widget for a given page.
Future<Image> buildPdfPageImage({
  required String path,
  required int pageNumber,
  int? targetWidth,
  int? targetHeight,
  BoxFit fit = BoxFit.contain,
}) async {
  final bytes = await renderPdfPageBytes(
    pdfPathOrAssetOrUrl: path,
    pageNumber: pageNumber,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
  return Image.memory(bytes, fit: fit);
}
