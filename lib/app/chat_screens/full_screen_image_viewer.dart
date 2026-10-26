import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';

class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final File? imageFile;

  const FullScreenImageViewer({super.key, required this.imageUrl, this.imageFile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(elevation: 0.0, backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white), systemOverlayStyle: SystemUiOverlayStyle.light),
      body: Container(color: Colors.black, child: Hero(tag: imageUrl, child: PhotoView(imageProvider: imageFile == null ? CachedNetworkImageProvider(imageUrl) : Image.file(imageFile!).image))),
    );
  }
}
