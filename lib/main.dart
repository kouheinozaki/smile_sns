import 'dart:io'; // ファイルのやりとり
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // 日付整える
import 'package:uuid/uuid.dart';
import 'package:path/path.dart'; // ファイルのパス整える
import 'package:image_picker/image_picker.dart'; // 画像の選択

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ml_vision/firebase_ml_vision.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'login.dart';

void main()  async{ // firebaseの初期設定
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyAIApp());
}

class MyAIApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "SMILE SNS",
      theme: ThemeData( // テーマを設定してる
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: LoginPage(),
    );
  }
}

class MainForm extends StatefulWidget {
  MainForm(this.user);

  final User user;

  @override
  _MainFormState createState() => _MainFormState();
}

class _MainFormState extends State<MainForm> {

  String _name =""; // ユーザーの名前を入れる変数
  String _processingMessage = "";
  final FaceDetector _faceDetector = FirebaseVision.instance.faceDetector(
      FaceDetectorOptions(
          mode: FaceDetectorMode.accurate, // 顔の精度上げるため
          enableLandmarks: true, // 目や鼻、口の計測を可能にする
          enableClassification: true // 笑顔の確率の計測
      )
  );
  final ImagePicker _picker = ImagePicker(); // ImagePickerのインスタンスを生成

  // 各ボタンを押された時のメソッド、画像を取得して処理を行うため カメラからか、端末内部からか判断
  void _getImageAndFindFace(BuildContext context, ImageSource imageSource) async {
    setState(() { // 今処理中と画面に表示
      _processingMessage = "Processing...";
    });
    // カメラもしくはギャラリーから画像を選択
    final PickedFile pickedImage = await _picker.getImage(source: imageSource);
    // 上の行の処理が終わったら下の行を処理
    final File imageFile = File(pickedImage.path);

    // 画像が取得できていれば、
    if (imageFile != null) {
      final FirebaseVisionImage visionImage = FirebaseVisionImage.fromFile(imageFile);
      // facesに格納、
      List<Face> faces = await _faceDetector.processImage(visionImage);
      // 画像に顔が写ってると処理
      if(faces.length >= 0){
        // クラウド上に保存する際のパス、uuidでダブらないようにv1で時刻に基づくuuid basenameは元のファイル名
        String imagePath = "/images/" + Uuid().v1() + basename(pickedImage.path);
        // イメージパスを使ってストレージのリファレンスを作る、それを使って保存
        Reference ref = FirebaseStorage.instance.ref().child(imagePath);
        // putFileでリファレンス・ファイルを指定してクラウド上に行うことができる。
        final TaskSnapshot storedImage = await ref.putFile(imageFile);
        // 非同期 上の処理が終わってから下の行 storedImageで保存された画像の情報を取得
        if(storedImage == null){
          // 画像の表示をするためにURLが必要、storedImageでURL取得、時間がかかるので非同期
          final String downloadUrl = await storedImage.ref.getDownloadURL();
          // 非同期 上の処理が終わってから下の処理
          // 最も大きい顔を見つける 最も大きい顔の笑顔を反映
          Face largestFace = findLargestFace(faces);

          // Firestoreに画像を保存
          FirebaseFirestore.instance.collection("smiles").add({
            "name": _name,
            "smile_prob": largestFace.smilingProbability,
            "image_url": downloadUrl,
            "date": Timestamp.now(),
          });
          Navigator.push(
              context, // Firestoreに投稿した後に次の画面に遷移 // 次の画面のインスタンスを生成
              MaterialPageRoute(builder: (context) => TimelinePage(),)
          );
        }
      }
    }
    // 空白の文字列
    setState(() {
      _processingMessage = "";
    });
  }
  // ループを使ってその顔の幅と高さを正したもので一番大きい物を返り値としてる
  Face findLargestFace(List<Face> faces){
    Face largestFace = faces[0];
    for (Face face in faces) {
      if(face.boundingBox.height+face.boundingBox.width >
          largestFace.boundingBox.height+largestFace.boundingBox.width){
        largestFace = face;
      }
    }
    return largestFace;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("SMILE SNS"),
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(icon: Icon(Icons.home), title: Text('Home')),
            BottomNavigationBarItem(icon: Icon(Icons.timeline), title: Text('Album'),),
            BottomNavigationBarItem(icon: Icon(Icons.chat), title: Text('Chat')),
          ],
          fixedColor: Colors.blueAccent,
          type: BottomNavigationBarType.fixed,),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Padding(padding: EdgeInsets.all(30.0)),
            Text(
                _processingMessage,
                style: TextStyle(
                  color: Colors.lightBlue,
                  fontSize: 32.0,
                )
            ),
            TextFormField(
              decoration: const InputDecoration(
                icon: Icon(Icons.person),
                hintText: "Please input your name.",
                labelText: "YOUR NAME",
              ),
              onChanged:(text){ // テキストを入力
                setState(() {_name = text;}); // 入力された名前が入る
              },
            )
          ],
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            FloatingActionButton(
              onPressed:(){_getImageAndFindFace(context, ImageSource.gallery);} ,
              tooltip: "Select Image",
              heroTag: "gallery",
              child: Icon(Icons.add_photo_alternate),
            ),
            Padding(padding: EdgeInsets.all(10.0)),
            FloatingActionButton(
              onPressed:(){_getImageAndFindFace(context, ImageSource.camera);} ,
              tooltip: "Take Photo",
              heroTag: "camera",
              child: Icon(Icons.add_a_photo),
            ),
          ],
        )
    );
  }
}

class TimelinePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("SMILE SNS"),
        ),bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
    BottomNavigationBarItem(icon: Icon(Icons.home), title: Text('Home')),
    BottomNavigationBarItem(icon: Icon(Icons.photo_album), title: Text('Album')),
    BottomNavigationBarItem(icon: Icon(Icons.chat), title: Text('Chat')),
    ],
      fixedColor: Colors.blueAccent,
      type: BottomNavigationBarType.fixed,),
        body: Container(
          child: _buildBody(context),
        )
    );
  }

  Widget _buildBody(BuildContext context) {
    // 現時刻におけるデータをsnapshotで取得
    return StreamBuilder<QuerySnapshot>(
      // collectionを指定、日付順番で降順指定 上位10個、listview新しい状態を維持
      stream: FirebaseFirestore.instance.collection("smiles").orderBy("date", descending: true).limit(10).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return LinearProgressIndicator();
        return _buildList(context, snapshot.data.docs);
      },
    );
  }
  // 各リストアイテムの設定を行う
  Widget _buildList(BuildContext context, List<DocumentSnapshot> snapList) {
    return ListView.builder(
        padding: const EdgeInsets.all(18.0),
        itemCount: snapList.length,
        itemBuilder: (context, i) {
          return _buildListItem(context, snapList[i]);
        }
    );
  }
  // 各リストアイテムに対応するsnapshotのデータを_dataに入れて、dateで日付を取り出す,
  // map型, toDateで変換 firebaseとdartで型が違う
  Widget _buildListItem(BuildContext context, DocumentSnapshot snap) {
    Map<String, dynamic> _data = snap.data();
    DateTime _datetime = _data["date"].toDate();
    // このフォーマットで時刻を整える
    var _formatter = DateFormat("MM/dd HH:mm");
    // 文字列に変換、postDateが投稿された時間
    String postDate = _formatter.format(_datetime);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical:9.0),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8.0), //　角丸
        ),
        child: ListTile(
          leading: Text(postDate),
          title: Text(_data["name"]),
          subtitle: Text("は"
                // 笑顔の確率を取得、100かけて%表示  // 小数点1位までの文字列にしてる
              + (_data["smile_prob"]*100.0).toStringAsFixed(1)
              + "%の笑顔です。"
          ),
          trailing: Text( // trailn一番右側に表示されるwidget
            // Iconを表示している
            _getIcon(_data["smile_prob"]),
            style: TextStyle(fontSize: 24,),
          ),
          onTap: (){
            Navigator.push(
                context,                               // URLを渡しているImagePageに
                MaterialPageRoute(builder: (context) => ImagePage(_data["image_url"]),)
            );
          },
        ),
      ),
    );
  }
  // 確率に応じた顔の表示
  String _getIcon(double smileProb){
    String icon = "";
    if(smileProb < 0.2){
      icon = "😧";
    }else if(smileProb < 0.4){
      icon ="😌";
    }else if(smileProb < 0.6){
      icon ="😀";
    }else if(smileProb < 0.8){
      icon ="😄";
    }else{
      icon ="😆";
    }
    return icon;
  }
}

class ImagePage extends StatelessWidget {
  String _imageUrl = "";

  // コンストラクタ
  ImagePage(String imageUrl){
    this._imageUrl = imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("SMILE SNS"),
      ),
      body: Center( // 画像を表示
        child: Image.network(_imageUrl),
      ),
    );
  }
}
