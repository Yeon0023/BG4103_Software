import 'dart:async';
import 'package:bg4102_software/Utilities/currentAddress.dart';
import 'package:bg4102_software/Utilities/sizeConfiguration.dart';
import 'package:bg4102_software/Utilities/utils.dart';
import 'package:bg4102_software/constats/routes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:lite_rolling_switch/lite_rolling_switch.dart';
import 'package:location/location.dart';
import 'package:liquid_progress_indicator/liquid_progress_indicator.dart';
import 'package:text_to_speech/text_to_speech.dart';
import 'package:twilio_flutter/twilio_flutter.dart';
import '../Utilities/customAppbar.dart';
import '../Utilities/customDrawer.dart';

class TestResultView extends StatefulWidget {
  const TestResultView({Key? key}) : super(key: key);

  @override
  State<TestResultView> createState() => _TestResultViewState();
}

class _TestResultViewState extends State<TestResultView> {
  final LatLng _initialcameraposition = const LatLng(20.5937, 78.9629);
  final Map<String, Marker> _markers = {};
  final String serviceUuid = "0x180A";
  final String bleFloat = "C8F88594-2217-0CA6-8F06-A4270B675D69";
  final String targetDeviceName = "ManoBreathalyser";
  final Location _location = Location();
  var location = Location();
  static const String startTestUuid = "0x2A57";
  static const String retrieveResultUuid = "0x8594";
  late GoogleMapController _mapController;
  // ignore: non_constant_identifier_names
  double BAC = 0.0; //!BAC is Blood Alcohol Content.
  // ignore: prefer_final_fields, unused_field
  String _indicatorText = "No Result";
  FlutterBluePlus flutterBlue = FlutterBluePlus.instance;
  StreamSubscription<ScanResult>? scanSubcription;
  bool? serviceEnabled;
  PermissionStatus? _permissionGranted;
  LocationData? locationData;
  LocationData? currentLocation;
  BluetoothDevice? targetDevice;
  BluetoothDeviceState? deviceState;
  BluetoothCharacteristic? startTestCharacteristic,
      retrieveResultCharacteristic;
  BluetoothDescriptor? targetDescriptor;
  String connectionText = "";
  TwilioFlutter? twilioFlutter;
  final firebaseUser = FirebaseAuth.instance.currentUser;
  final FirebaseAuth auth = FirebaseAuth.instance;
  String name = '';
  String ec = '';
  String ecp = '';
  String drinkingstatus = '';
  String dialogContent = '';
  String testresults = '';
  get value => readData(startTestCharacteristic!);
  final formkey = GlobalKey<FormState>();
  final userCollections = FirebaseFirestore.instance.collection("users");
  bool _isloading = false;
  bool _isBTConnected = false;
  TextToSpeech tts = TextToSpeech();

  @override
  void initState() {
    twilioFlutter = TwilioFlutter(
        accountSid: 'AC4594fe0673b475bd0dbee2770e2f8eda',
        authToken: 'dc32274542c684524eb629b6cf8a40df',
        twilioNumber: '+13854062421');
    _getPermission();
    _getCurrentLocation();

    super.initState();
    _getdata();
  }

  //* Add entry to firestore for records.
  Future<void> addEntry() {
    resultCondition(BAC);
    var now = DateTime.now();
    var formatter = DateFormat('dd-MM-yyyy – HH:mm');
    final String formattedDate = formatter.format(now);
    return FirebaseFirestore.instance.collection(firebaseUser!.uid).add(
      {
        'DatenTime': formattedDate,
        'Result': _indicatorText,
        'Location': Address,
        'Status': drinkingstatus
      },
    );
  }

  //?--------------------------------THIS IS SMS SYSTEM----------------------------------------------------------------
  //Firebase Cloud
  void _getdata() async {
    FirebaseFirestore.instance
        .collection('users')
        .doc(firebaseUser!.uid)
        .snapshots()
        .listen((userData) {
      setState(() {
        name = userData.data()!['Name'];
        ec = userData.data()!['Emergency Contact'];
        ecp = userData.data()!['Emergency contact person'];
      });
    });
  }

  // ignore: non_constant_identifier_names
  Future<void> _sendSms(String Address) async {
    twilioFlutter?.sendSMS(
        toNumber: "+65$ec",
        messageBody:
            'Hi $ecp, $name is drunk currently. Please come and get $name at $Address.');
  }

  //?-----------------------------------This is BlueTooth Section.------------------------------------------------------
  startScan() {
    setState(() {
      connectionText = "Start Scanning";
    });

    scanSubcription = flutterBlue.scan().listen((scanResult) {
      if (scanResult.device.name == targetDeviceName) {
        print('DEVICE found');
        stopScan();
        setState(() {
          connectionText = "Found Target Device";
        });
        targetDevice = scanResult.device;
        connectToDevice();
      }
    }, onDone: () => stopScan());
  }

  stopScan() {
    flutterBlue.stopScan();
    scanSubcription?.cancel();
    scanSubcription = null;
  }

  connectToDevice() async {
    if (targetDevice == null) return;
    setState(
      () {
        connectionText = "Device Connecting";
      },
    );
    await targetDevice!.connect();
    print('DEVICE CONNECTED');
    tts.speak('DEVICE CONNECTED');
    setState(() {
      connectionText = "Device Connected";
    });
    discoverServices();
  }

  disconnectFromDevice() {
    if (targetDevice == null) return;
    targetDevice!.disconnect();
    deviceState = BluetoothDeviceState.disconnected;
    setState(
      () {
        connectionText = "Device Disconnected";
        tts.speak('DEVICE DISCONNECTED');
      },
    );
  }

  bool _isBlueToothConnected = false;
  toggleBlueTooth() {
    if (_isBlueToothConnected == true) {
      disconnectFromDevice();
    } else {
      startScan();
    }
    setState(
      () {
        _isBlueToothConnected = !_isBlueToothConnected;
      },
    );
  }

  //* BlueTooth Connection indicator.
  final connectedText = Text.rich(
    TextSpan(
      children: [
        const WidgetSpan(child: Icon(Icons.bluetooth_connected_rounded)),
        TextSpan(
          text: ' BlueTooth Connected',
          style: GoogleFonts.bebasNeue(
            color: Colors.blue[700],
            fontSize: 20,
          ),
        ),
      ],
    ),
  );
  final disconnectedText = Text.rich(
    TextSpan(
      children: [
        const WidgetSpan(child: Icon(Icons.bluetooth_disabled_rounded)),
        TextSpan(
          text: ' BlueTooth Disconnected',
          style: GoogleFonts.bebasNeue(
            color: Colors.red[700],
            fontSize: 20,
          ),
        ),
      ],
    ),
  );
  Widget _connectionStatus() => StreamBuilder<BluetoothDeviceState>(
        stream: targetDevice?.state,
        initialData: BluetoothDeviceState.disconnected,
        builder: (c, snapshot) {
          if (snapshot.data == BluetoothDeviceState.connected) {
            return Container(
              child: connectedText,
            );
          } else {
            const CircularProgressIndicator();
          }
          return Container(
            child: disconnectedText,
          );
        },
      );

  //* Connect BlueTooth slider.
  Widget _blueToothToogleSlide() => Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.blockSizeHorizontal * 30),
          child: LiteRollingSwitch(
            //initial value
            value: false,
            width: SizeConfig.blockSizeHorizontal * 50,
            textOn: 'Slide to disconnect',
            textOff: 'Slide to connect',
            colorOn: Colors.blue,
            colorOff: Colors.red,
            iconOn: Icons.arrow_circle_left_sharp,
            iconOff: Icons.arrow_circle_right_sharp,
            textSize: 15,
            onChanged: (bool state) {
              toggleBlueTooth();
            },
            onDoubleTap: () {},
            onSwipe: () {},
            onTap: () {},
          ),
        ),
      );

  discoverServices() async {
    if (targetDevice == null) return;

    List<BluetoothService> services = await targetDevice!.discoverServices();
    // ignore: avoid_function_literals_in_foreach_calls
    services.forEach(
      (service) {
        if ('0x${service.uuid.toString().toUpperCase().substring(4, 8)}' ==
            serviceUuid) {
          // ignore: avoid_function_literals_in_foreach_calls
          service.characteristics.forEach(
            (characteristic) {
              switch (
                  "0x${characteristic.uuid.toString().toUpperCase().substring(4, 8)}") {
                case startTestUuid:
                  startTestCharacteristic = characteristic;
                  break;
                case retrieveResultUuid:
                  retrieveResultCharacteristic = characteristic;
                  break;
                default:
              }
            },
          );
        }
      },
    );
  }

  startTest(int data) async {
    if (startTestCharacteristic == null) return;
    await startTestCharacteristic!.write([data]);
  }

  Future<List<int>> readData(BluetoothCharacteristic characteristic) async {
    return await characteristic.read();
  }
  //?-------------------------------------------------------------------------------------------------------------------

  //*Get the current location of device in lat and long.
  void _getPermission() async {
    var serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }
    _permissionGranted = await location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) {
        return;
      }
    }
  }

  //* Get current Location for Icon only.
  Future<void> _getCurrentLocation() async {
    Location location = Location();
    location.getLocation().then(
      (location) async {
        currentLocation = location;
        List<double> currentCoordinate = [];
        currentCoordinate
            .addAll([currentLocation!.latitude!, currentLocation!.longitude!]);
        await GetCurrentAddress(currentCoordinate);
        if (!mounted) return;
        setState(() {});
      },
    );
  }

  //* Get current Location for camera position.
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _location.onLocationChanged.listen((LocationData currentLocation) {
      _mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target:
                LatLng(currentLocation.latitude!, currentLocation.longitude!),
            zoom: 15,
          ),
        ),
      );
      addMarker(
        'Current Location',
        LatLng(currentLocation.latitude!, currentLocation.longitude!),
      );
    });
  }

  //* Add marker on the map.
  addMarker(String id, LatLng currentLocation) async {
    var markerIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(),
      'assets/images/beerIcon65.png',
    );
    var marker = Marker(
      markerId: MarkerId(id),
      position: currentLocation,
      infoWindow: InfoWindow(
        title: 'Your Current location',
        snippet: LatLng(
          currentLocation.latitude,
          currentLocation.longitude,
        ).toString(),
      ),
      icon: markerIcon,
    );
    _markers[id] = marker;
    if (!mounted) return;
    setState(() {});
  }

  //* Draw Google Map on page.
  Widget _drawGoogleMap() => Container(
        height: SizeConfig.blockSizeVertical * 40,
        width: SizeConfig.blockSizeHorizontal * 100,
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.blueGrey,
            width: 1.5,
          ),
        ),
        child: GoogleMap(
          mapType: MapType.normal,
          initialCameraPosition: CameraPosition(target: _initialcameraposition),
          onMapCreated: _onMapCreated,
          markers: _markers.values.toSet(),
        ),
      );

  Path _buildBoatPath() {
    return Path()
      ..moveTo(50.01, 19.91)
      ..lineTo(180.03, 19.07)
      ..quadraticBezierTo(180.39, 89.67, 170.47, 109.97)
      ..cubicTo(162.51, 129.61, 150.54, 159.57, 150.18, 180.56)
      ..quadraticBezierTo(150.18, 198.06, 160.02, 229.85)
      ..lineTo(69.59, 229.89)
      ..quadraticBezierTo(80.27, 193.42, 80.38, 180.69)
      ..cubicTo(80.28, 159.5, 67.13, 129.81, 59.97, 110.34)
      ..quadraticBezierTo(50.11, 90.14, 50.01, 19.91)
      ..close();
  }

  //*Alcohol level Indicator
  Widget _drawIndicator() => SizedBox(
        height: 230,
        width: 230,
        child: LiquidCustomProgressIndicator(
          value: BAC, // Defaults to 0.5.
          valueColor: AlwaysStoppedAnimation(
            BAC >= 0.8
                ? Colors.red
                : BAC > 0.2 && BAC < 0.8
                    ? Colors.orange
                    : Colors.green,
          ), // Defaults to the current Theme's accentColor.
          backgroundColor:
              Colors.white, // Defaults to the current Theme's backgroundColor.
          direction: Axis
              .vertical, // The direction the liquid moves (Axis.vertical = bottom to top, Axis.horizontal = left to right). Defaults to Axis.vertical.
          center: _isloading
              ? CircularProgressIndicator(
                  color: Colors.teal[800],
                  backgroundColor: Colors.teal[100],
                  strokeWidth: 6.0,
                )
              : Text(
                  _indicatorText,
                  style: GoogleFonts.bebasNeue(
                    color: Colors.black,
                    fontSize: 18,
                    // fontWeight: FontWeight.bold,
                  ),
                ),
          shapePath: _buildBoatPath(),
        ),
      );

  //* Start Test Button.
  Widget _toastmaker() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18.0),
        child: SizedBox(
          height: 55,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              elevation: 5,
              backgroundColor: Colors.amber[600],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18.0),
              ),
            ),
            child: Text(
              'Check Alcohol Level',
              style: GoogleFonts.bebasNeue(
                textStyle: const TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                ),
              ),
            ),
            onPressed: () async {
              _isloading = true;
              tts.speak('Starting test now');
              await Fluttertoast.showToast(
                msg: "Starting Test Now !",
                toastLength: Toast.LENGTH_LONG,
                gravity: ToastGravity.BOTTOM,
                timeInSecForIosWeb: 1,
                backgroundColor: Colors.blue[900],
                textColor: Colors.white,
                fontSize: 17,
              );
              int data = 1;
              await startTest(data);
              List<int> result = await readData(startTestCharacteristic!);
              if (result.first == 1) {
                _isloading = false;
                List<int> result =
                    await readData(retrieveResultCharacteristic!);
                // ignore: no_leading_underscores_for_local_identifiers
                double _value = convertByteArray(result);

                BAC = relativeToAlcohol(_value);
                String resultIndicatorText = _value.toString();
                _indicatorText = "$resultIndicatorText%";
                _statusReader(BAC, _indicatorText);
                Timer(
                  const Duration(seconds: 4),
                  () {
                    resultDialog();
                  },
                );
                addEntry();
                setState(() {});
              } else {
                print("Error, try again...");
              }
            },
          ),
        ),
      );

  void _statusReader(double BAC, String _indicatorText) {
    if (BAC >= 0.8) {
      tts.speak("your alcolhol level is $_indicatorText"
          "You are Drunk, please do not drive");
    } else if (BAC > 0.0 && BAC < 0.8) {
      tts.speak("your alcolhol level is $_indicatorText"
          "You are within limit, play a game to ensure you are sober");
    } else {
      tts.speak("your alcolhol level is $_indicatorText"
          "You are sober, Go to Tips to learn more about alcohol use disorder");
    }
  }

  void resultCondition(double BAC) {
    if (BAC >= 0.8) {
      drinkingstatus = "Drinking Status: Drunk";
      dialogContent =
          "\n\nPLEASE DO NOT DRIVE ! \n\nBreathX have contacted your emergency contact about your location.";
      _sendSms(Address);
    } else if (BAC > 0.0 && BAC < 0.8) {
      drinkingstatus = "Drinking Status: Within Limit";
      dialogContent =
          "\n\nYou are within limit, Ensure you are Sober by playing a GAME to test your focus.";
    } else {
      drinkingstatus = "Drinking Status: Sober";
      dialogContent =
          "\n\nYou are Sober, Go to Tips to learn more about alcohol use disorder (AUD)!";
    }
  }

  // ignore: non_constant_identifier_names
  void resultDialog() {
    resultCondition(BAC);
    var now = DateTime.now();
    var formatter = DateFormat('\ndd-MM-yyyy – HH:mm');
    final String formattedDate = formatter.format(now);
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("BreathX Result"),
        content: Text(
          '$drinkingstatus $dialogContent \n\nDate & Time of Record: $formattedDate',
          textAlign: TextAlign.center,
        ),
        actions: <Widget>[
          BAC < 0.8
              ? BAC == 0.0
                  ? TextButton(
                      onPressed: () {
                        disconnectFromDevice();
                        Navigator.of(ctx).pushNamed(learnpageRoute);
                      },
                      child: Container(
                        color: Colors.teal[500],
                        padding: const EdgeInsets.all(14),
                        child: const Text("Tips"),
                      ),
                    )
                  : TextButton(
                      onPressed: () {
                        disconnectFromDevice();
                        Navigator.of(ctx).pushNamed(gamePageRoute);
                      },
                      child: Container(
                        color: Colors.teal[500],
                        padding: const EdgeInsets.all(14),
                        child: const Text("Play Game"),
                      ),
                    )
              : Container(),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: Container(
              color: Colors.teal[500],
              padding: const EdgeInsets.all(14),
              child: const Text("okay"),
            ),
          ),
        ],
      ),
    );
  }

  //*Final View of Test Result page.
  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      drawer: const CustomDrawer(),
      appBar: CustomAppbar(
        title: 'Test Result',
        fontSize: 25,
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              if (_isBlueToothConnected == true) {
                disconnectFromDevice();
              }
              Navigator.of(context).pushNamed(homePageRoute);
            },
          ),
        ],
        leading: null,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: SizeConfig.blockSizeVertical * 85,
              // color: Colors.blue,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 5,
                    child: _connectionStatus(),
                  ),
                  Positioned(
                    top: 40,
                    child: _blueToothToogleSlide(),
                  ),
                  Positioned(
                    top: 125,
                    child: Container(
                      width: SizeConfig.safeBlockHorizontal * 100,
                      height: SizeConfig.blockSizeVertical * 32,
                      // color: Colors.amber,
                      child: Image.asset(
                        "assets/images/pic1.png",
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 95,
                    child: _drawIndicator(),
                  ),
                  Positioned(
                    bottom: 0,
                    child: _drawGoogleMap(),
                  ),
                  Positioned(
                    top: 320,
                    child: _toastmaker(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_isBlueToothConnected == true) {
      disconnectFromDevice();
    }
    stopScan();
    _drawGoogleMap();
    super.dispose();
  }
}

//!-------------------------------------END----------------------------------------------------------------------------
