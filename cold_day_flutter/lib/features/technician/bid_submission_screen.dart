import 'package:flutter/material.dart';

class BidSubmissionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Submit Bid")),
      body: Form(
        child: Column(
          children: [
            TextField(decoration: InputDecoration(labelText: "Transport Cost")),
            TextField(decoration: InputDecoration(labelText: "Diagnosis Cost")),
          ],
        ),
      ),
    );
  }
}
