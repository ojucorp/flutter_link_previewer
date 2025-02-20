import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Element;
import 'package:flutter_chat_types/flutter_chat_types.dart'
    show PreviewData, PreviewDataImage;
import 'package:flutter_link_previewer/src/cp949.dart';
import 'package:html/dom.dart' show Document, Element;
import 'package:html/parser.dart' as parser show parse;
import 'package:http/http.dart' as http show get;
import 'types.dart';

extension FileNameExtention on String {
  /// Returns the last part of the path string after the . char
  String get fileExtension {
    return split('/').last.split('.').last;
  }
}

String? _getMetaContent(Document document, String propertyValue) {
  final meta = document.getElementsByTagName('meta');
  final element = meta.firstWhere(
    (e) => e.attributes['property'] == propertyValue,
    orElse: () => meta.firstWhere(
      (e) => e.attributes['name'] == propertyValue,
      orElse: () => Element.tag(null),
    ),
  );

  return element.attributes['content']?.trim();
}

String _getCharset(Document document) {
  final emptyElement = Element.tag(null);
  final meta = document.getElementsByTagName('meta');
  final element = meta.firstWhere(
    (e) => e.attributes.containsKey('charset'),
    orElse: () => emptyElement,
  );
  if (element == emptyElement) return 'utf-8';
  return element.attributes['charset']!.toLowerCase();
}

String? _getTitle(Document document) {
  final titleElements = document.getElementsByTagName('title');
  if (titleElements.isNotEmpty) return titleElements.first.text;

  return _getMetaContent(document, 'og:title') ??
      _getMetaContent(document, 'twitter:title') ??
      _getMetaContent(document, 'og:site_name');
}

String? _getDescription(Document document) {
  return _getMetaContent(document, 'og:description') ??
      _getMetaContent(document, 'description') ??
      _getMetaContent(document, 'twitter:description');
}

List<String> _getImageUrls(Document document, String baseUrl) {
  final meta = document.getElementsByTagName('meta');
  var attribute = 'content';
  var elements = meta
      .where(
        (e) =>
            e.attributes['property'] == 'og:image' ||
            e.attributes['property'] == 'twitter:image',
      )
      .toList();

  if (elements.isEmpty) {
    elements = document.getElementsByTagName('img');
    attribute = 'src';
  }

  return elements.fold<List<String>>([], (previousValue, element) {
    final actualImageUrl = _getActualImageUrl(
      baseUrl,
      element.attributes[attribute]?.trim(),
    );

    return actualImageUrl != null
        ? [...previousValue, actualImageUrl]
        : previousValue;
  });
}

String? _getActualImageUrl(String baseUrl, String? imageUrl) {
  if (imageUrl == null || imageUrl.isEmpty || imageUrl.startsWith('data')) {
    return null;
  }

  if (['svg', 'gif'].contains(imageUrl.fileExtension)) return null;

  if (imageUrl.startsWith('//')) imageUrl = 'https:$imageUrl';

  if (!imageUrl.startsWith('http')) {
    if (baseUrl.endsWith('/') && imageUrl.startsWith('/')) {
      imageUrl = '${baseUrl.substring(0, baseUrl.length - 1)}$imageUrl';
    } else if (!baseUrl.endsWith('/') && !imageUrl.startsWith('/')) {
      imageUrl = '$baseUrl/$imageUrl';
    } else {
      imageUrl = '$baseUrl$imageUrl';
    }
  }

  return imageUrl;
}

Future<Size> _getImageSize(String url) {
  final image = Image.network(url);
  final completer = Completer<Size>();
  final listener = ImageStreamListener(
    (ImageInfo info, bool _) => completer.complete(
      Size(
        height: info.image.height.toDouble(),
        width: info.image.width.toDouble(),
      ),
    ),
    onError: (Object exception, StackTrace? stackTrace) {
      completer.complete(const Size(height: 0, width: 0));
    }
  );

  image.image.resolve(ImageConfiguration.empty).addListener(listener);
  return completer.future;
}

Future<String> _getBiggestImageUrl(List<String> imageUrls) async {
  if (imageUrls.length > 3) {
    imageUrls.removeRange(3, imageUrls.length);
  }
  var currentUrl = imageUrls[0];
  var currentArea = 0.0;

  await Future.forEach(imageUrls, (String url) async {
    await _getImageSize(url).then((size) {
      final area = size.width * size.height;
      if (area > currentArea) {
        currentArea = area;
        currentUrl = url;
      }
    }).catchError((e) {
      print('failed to get image ${e.toString()}');
    });
  });

  return currentUrl;
}

bool isYoutubeLink(final String host) {
  if (host.startsWith("youtu.be") ||
      host.startsWith("youtube.com") ||
      host.startsWith("www.youtube.com")) {
    return true;
  }
  return false;
}

String getYoutubeDocId(final Uri uri) {
  if (uri.queryParameters.containsKey('v')) {
    return uri.queryParameters['v'].toString();
  } else if (uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.first;
  }
  return '';
}

Future<PreviewData> getYoutubePreviewData(final String docId, final String previewDataUrl) async {
  final embedUrl =
      'https://www.youtube.com/oembed?url=http://www.youtube.com/watch?v=$docId&format=json';

  final imgUrl = 'https://img.youtube.com/vi/$docId/mqdefault.jpg';

  final uri = Uri.parse(embedUrl);
  final response = await http.get(uri);
  final jsonData = jsonDecode(response.body) as Map<String, dynamic>;

  final previewDataImage = PreviewDataImage(
    width: jsonData.containsKey('thumbnail_width')
        ? double.parse(jsonData['thumbnail_width'].toString())
        : 480,
    height: jsonData.containsKey('thumbnail_height')
        ? double.parse(jsonData['thumbnail_height'].toString())
        : 360,
    url: imgUrl,
  );

  return PreviewData(
    description: '',
    image: previewDataImage,
    link: previewDataUrl,
    title: jsonData['title'].toString() + ' - Youtube',
  );
}

/// Parses provided text and returns [PreviewData] for the first found link
Future<PreviewData> getPreviewData(String text) async {
  const previewData = PreviewData();

  String? previewDataDescription;
  PreviewDataImage? previewDataImage;
  String? previewDataTitle;
  String? previewDataUrl;

  try {
    var url = text;
    if (!url.startsWith('http')) {
      url = 'https://' + url;
    }
    previewDataUrl = url;
    final uri = Uri.parse(url);
    if (isYoutubeLink(uri.host)) {
      final docId = getYoutubeDocId(uri);
      if (docId.isNotEmpty) {
        return getYoutubePreviewData(docId, previewDataUrl);
      }
    }

    final response = await http.get(uri);
    var document = parser.parse(response.body);

    final charset = _getCharset(document);
    if (charset != 'utf-8' && charset != 'euc-kr') {
      return previewData;
    }
    if (charset == 'euc-kr') {
      document = parser.parse(CP949.decode(response.bodyBytes));
    }

    final title = _getTitle(document);
    if (title != null) {
      previewDataTitle = title.trim();
    }

    final description = _getDescription(document);
    if (description != null) {
      previewDataDescription = description.trim();
    }

    final imageUrls = _getImageUrls(document, url);

    Size imageSize;
    String imageUrl;

    if (imageUrls.isNotEmpty) {
      imageUrl = imageUrls.length == 1
          ? imageUrls[0]
          : await _getBiggestImageUrl(imageUrls);

      imageSize = await _getImageSize(imageUrl);
      previewDataImage = PreviewDataImage(
        height: imageSize.height,
        url: imageUrl,
        width: imageSize.width,
      );
    }
    return PreviewData(
      description: previewDataDescription,
      image: previewDataImage,
      link: previewDataUrl,
      title: previewDataTitle,
    );
  } catch (e) {
    return PreviewData(
      description: previewDataDescription,
      image: previewDataImage,
      link: previewDataUrl,
      title: previewDataTitle,
    );
  }
}

/// Regex to find all links in the text
const REGEX_LINK = r'(?:(?:https?|ftp):\/\/)?[\w/\-?=%.]+\.[\w/\-?=%.]+';
