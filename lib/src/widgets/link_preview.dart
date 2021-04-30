import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' show PreviewData;
import 'package:flutter_linkify/flutter_linkify.dart' hide UrlLinkifier;
import 'package:url_launcher/url_launcher.dart';
import '../url_linkifier.dart' show UrlLinkifier;
import '../utils.dart' show getPreviewData;

/// A widget that renders text with highlighted links.
/// Eventually unwraps to the full preview of the first found link
/// if the parsing was successful.
class LinkPreview extends StatefulWidget {
  // ignore: use_key_in_widget_constructors
  const LinkPreview({
    required this.text,
    required this.width,
    required this.maxImageHeight,
    this.textStyle,
    this.metadataTextStyle,
    this.metadataTitleStyle,
  });

  /// Text used for parsing
  final String text;

  /// Width of the [LinkPreview] widget
  final double width;

  /// Max hidth of the image widget
  final double maxImageHeight;

  /// Style of the provided text
  final TextStyle? textStyle;

  /// Style of preview's description
  final TextStyle? metadataTextStyle;

  /// Style of preview's title
  final TextStyle? metadataTitleStyle;
  
  @override
  _LinkPreviewState createState() => _LinkPreviewState();
}

class _LinkPreviewState extends State<LinkPreview> {
  Future<PreviewData>? _fetchData;

  @override
  void initState() {
    super.initState();
    _fetchData = getPreviewData(widget.text);
  }

  Future<void> _onOpen(LinkableElement link) async {
    if (await canLaunch(link.url)) {
      await launch(link.url);
    } else {
      throw 'Could not launch $link';
    }
  }

  Widget _bodyWidget(PreviewData data, String text, double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _titleWidget(data.title ?? '제목없음'),
            ],
          ),
        ),
        if (data.image?.url != null) _imageWidget(data.image!.url, width),
      ],
    );
  }

  Widget _containerWidget({
    required double width,
    bool withPadding = false,
    required Widget child,
  }) {
    return Container(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    );
  }

  Widget _descriptionWidget(String description) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Text(
        description,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: widget.metadataTextStyle,
      ),
    );
  }

  Widget _imageWidget(String url, double width) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: widget.maxImageHeight,
      ),
      width: width,
      margin: const EdgeInsets.only(top: 8),
      child: Image.network(
        url,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
      ),
    );
  }

  Widget _minimizedBodyWidget(PreviewData data, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Linkify(
          linkifiers: [UrlLinkifier()],
          maxLines: 100,
          onOpen: _onOpen,
          options: const LinkifyOptions(
            defaultToHttps: true,
            humanize: false,
            looseUrl: true,
          ),
          text: text,
          style: widget.textStyle,
        ),
        if (data.title != null || data.description != null)
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (data.title != null) _titleWidget(data.title!),
                      if (data.description != null)
                        _descriptionWidget(data.description!),
                    ],
                  ),
                ),
              ),
              if (data.image?.url != null)
                _minimizedImageWidget(data.image!.url),
            ],
          ),
      ],
    );
  }

  Widget _minimizedImageWidget(String url) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(
        Radius.circular(12),
      ),
      child: SizedBox(
        height: 48,
        width: 48,
        child: Image.network(url),
      ),
    );
  }

  Widget _plainTextWidget() {
    return _containerWidget(
      width: widget.width,
      withPadding: true,
      child: Linkify(
        linkifiers: [UrlLinkifier()],
        maxLines: 100,
        onOpen: _onOpen,
        options: const LinkifyOptions(
          defaultToHttps: true,
          humanize: false,
          looseUrl: true,
        ),
        text: widget.text,
        style: widget.textStyle,
      ),
    );
  }

  Widget _titleWidget(String title) {
    final style = widget.metadataTitleStyle ??
        const TextStyle(
          fontWeight: FontWeight.bold,
        );

    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PreviewData>(
      initialData: null,
      future: _fetchData,
      builder: (BuildContext context, AsyncSnapshot<PreviewData> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.hasError ||
            snapshot.data == null) return _plainTextWidget();

        final aspectRatio = snapshot.data!.image == null
            ? null
            : snapshot.data!.image!.width / snapshot.data!.image!.height;

        final _width = aspectRatio == 1 ? widget.width : widget.width - 32;

        return _containerWidget(
          width: widget.width,
          withPadding: aspectRatio == 1,
          child: aspectRatio == 1
              ? _minimizedBodyWidget(snapshot.data!, widget.text)
              : _bodyWidget(snapshot.data!, widget.text, _width),
        );
      },
    );
  }
}
