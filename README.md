# PDF to XML converter
This project was made for CS493 Language Reclamation & Revitalization by:
- Katy Kochte
- Jenae Matson
- Grace Kim
- Jonathan Brough**
- Kohlby Vierthaler**

**Note: Worked alongside other groups in addition to contributing to this project.

## Install & Run
### Prerequisites
To use this app as it is, you must have the Flutter SDK and Git installed on your device. 
You can find instructions here: 
- [Flutter SDK](https://docs.flutter.dev/install)
- [Git](https://git-scm.com/install/)

### Running eBookMaker
First clone this git repository, then, in the repo directory, run:
```bash
flutter run
```
There may be a few other options that appear, such as what device to run the app on. Follow the instructions and choose what you prefer. The app should open on the selected option. 

## Using eBookMaker
When first running the app, the home screen looks something like this: 

<img width="1440" height="813" alt="Screenshot 2025-12-03 at 4 56 17 PM" src="https://github.com/user-attachments/assets/a848f1c4-3050-421e-81da-1648fecfbe01" />

## Documentation
To modify this app, there are two file that most of the work is in. They can be found in:
```bash
eBookMaker/lib/widgets/
```
In this directory there are two files, `app.dart` and `pdfrx_view.dart`. 
- `app.dart` is the main UI handler for eBookMaker. It handles our layout and other UI features.
- `pdfrx_view.dart` is the PDF viewer and selection manager for our app. It provides a PDF viewing interface using pdfrx.


# Libraries:
* [pdfrx](https://pub.dev/packages/pdfrx)
* [file_selector](https://pub.dev/packages/file_selector)
* [image](https://pub.dev/packages/image)

Links:
* [pdfrx Demo Website](https://github.com/espresso3389/pdfrx/tree/master/packages/pdfrx/example/viewer)
