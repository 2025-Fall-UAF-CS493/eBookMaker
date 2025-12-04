# PDF to XML Converter
This app converts PDFs to XML files by allowing the user to draw boxes on and attach labels to text and images, then export the selections as an XML file. 

This project was made for **CS493 Language Reclamation & Revitalization** by:

- Katy Kochte
- Jenae Matson
- Grace Kim
- Jonathan Brough**
- Kohlby Vierthaler**

> **Worked alongside other groups in addition to contributing to this project.

## Quick Links
- [Install & Run](#install--run)
- [Using eBookMaker](#using-ebookmaker)
- [Documentation](#documentation)
- [Libraries](#libraries)
- [Related Links](#related-links)

## Install & Run
### Prerequisites
To use this app as it is, you must have the **Flutter SDK** and **Git** installed on your device. 
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

### Home Menu
When first running the app, there is a sample PDF preloaded into the app, which is what appears on the screen.

![Screenshot of app homepage](https://github.com/user-attachments/assets/a848f1c4-3050-421e-81da-1648fecfbe01)

  
The top-right of the interface includes several buttons:

| **Feature** | **Description** |  |
|--------|-------------|--------|
| **Select** | Allows user to draw boxes on the PDF and to attach labels. | ![select](https://github.com/user-attachments/assets/3a3041d8-71f1-46f6-b557-94c2737aa589) |
| **Clear All** | Remove all selections. | ![clearall](https://github.com/user-attachments/assets/2e685f9d-2c33-4b23-a9cf-83fef6323630) |
| **Export** | Export selections as XML. | ![export](https://github.com/user-attachments/assets/7be10f1d-ac6e-4051-9a5b-cf4108af1ec8) |
| **Open File** | Upload a PDF. | ![open](https://github.com/user-attachments/assets/10c95a9b-889d-4c61-8bde-9b0f3a03f781)|
| **Help** | Open the help menu. | ![help](https://github.com/user-attachments/assets/2ae2cc0c-4dcf-4389-a33e-67fd1b999e96) |

### Sidebar
Clicking on a selection will open a sidebar on the right. It has a description of what's in the selection and some options to edit or delete the selection.

![sidebar](https://github.com/user-attachments/assets/56b3d6c8-2d59-4807-babb-df5ba7257a92)

## Documentation
To modify this app, most of the work can be found in:
```bash
eBookMaker/lib/widgets/
```
In this directory there are two files, `app.dart` and `pdfrx_view.dart`. 
- `app.dart` is the main UI handler for eBookMaker. It handles our layout and other UI features.
- `pdfrx_view.dart` is the PDF viewer and selection manager for our app. It provides a PDF viewing interface using pdfrx.

#### Jump To:
- [File: `app.dart`](#file-appdart)
- [File: `pdfrx_view.dart`](#file-pdfrx_viewdart)
- [XML File Export](#xml-file-export)

### File: `app.dart`
- Worked on by Katy Kochte, Jenae Matson, and Grace Kim.

`app.dart` handles the GUI and functionality of the eBook Maker app, including PDF loading, selection, export, and help dialogs.

#### Main Classes

`EbookMaker`
- Entry point of the app.
- Sets app theme, fonts, and home page.

`HomePage`
- Main screen with an app bar.
- Displays the `PDFSelectionWindow`.

`PDFSelectionWindow`
- Displays PDFs and handles user interactions.
- Properties:
  - Select Mode: Draw boxes on text or images.
  - Clear All: Remove all selections.
  - Export: Save selections as XML.
  - Open File: Load a new PDF.
  - Help: Shows a guide on using the app.
- Uses `ValueNotifier` to update the UI when selections, exports, or PDFs change.

`Widgets`
- `MaterialApp` & `Scaffold`
- `AppBar`
- `Column`, `Row`, `Padding` for layout
- `FilledButton.icon` for top buttons
- `PDF` (from pdfrx_view.dart) for displaying PDFs
- `AlertDialog` for help

---
### File: `pdfrx_view.dart`
- Worked on by Katy Kochte, Jenae Matson, and Grace Kim.

`pdfrx_view.dart` implements the PDF viewer and annotation system using the pdfrx framework. Handles text and image selection, labeling, editing, and exporting annotations to XML.

#### Main Classes

`PDF` (StatefulWidget)
- Main container for the PDF viewer and annotation system.
- Properties:
  - `selectModeNotifier`: Toggles selection mode on/off
  - `documentRef`: Reference to the loaded PDF document
  - `exportTrigger`: Triggers export functionality
  - `clearAllTrigger`: Triggers clearing all selections

`_PDFState`
- Manages the state of the PDF viewer and annotation system.
- Key features:
  - PDF rendering and display
  - Text and image selection handling
  - Annotation storage and management
  - Sidebar UI for editing annotations
  - Export to XML functionality

`TextSelection`
- Represents a user-selected text region in the PDF.
- Attributes: text content, position bounds, page number, label, color, language

`PdfMarker`
- Visual overlay for text selections in the PDF.
- Attributes: position bounds, page number, label, color, visual index

`ImageAnnotation`
- Represents a user-selected image region in the PDF.
- Attributes: image data, filename, position bounds, page number, label type, custom name, color

`Widgets`
- `PdfViewer`: Core PDF rendering component from pdfrx
- `OverlayEntry`: For selection rectangles and label popups
- `GestureDetector`: Handles tap, pan, and double-tap gestures
- `ValueListenableBuilder`: Reactive UI updates for sidebar
- `DropdownButton`: For label and language selection
- `AlertDialog`: For initial annotation labeling
- `SnackBar`: For user feedback messages

---
### XML File Export

- Located in `pdfrx_view.dart`
- Worked on by Jonathan Brough and Kohlby Vierthaler.

Generates structured XML containing all text and image annotations and saves it to a user-selected location.

#### Features
- **XML Generation**: Creates a complete XML file with all annotations.
- **File Saving**: Uses platform file picker to save to user's chosen location.
- **Image Export**: Extracted images saved as separate PNG files.
- **Data Structure**: Organized XML with text and image sections.

#### List of Current Labels/Tags
| Label / Type    | Category | Corresponding XML Tag | Color                 |
|-----------------|----------|---------------------|----------------------|
| Title           | Text     | `<textExtraction><label>Title</label></textExtraction>` | Blue (#0000FF)       |
| Caption         | Text     | `<textExtraction><label>Caption</label></textExtraction>` | Green (#008000)      |
| Paragraph       | Text     | `<textExtraction><label>Paragraph</label></textExtraction>` | Orange (#FFA500)     |
| Author          | Text     | `<textExtraction><label>Author</label></textExtraction>` | Purple (#800080)     |
| Figure          | Image    | `<imageExtraction><type>Figure</type></imageExtraction>` | Cyan (#00FFFF)       |
| Diagram         | Image    | `<imageExtraction><type>Diagram</type></imageExtraction>` | Indigo (#4B0082)     |
| Photo           | Image    | `<imageExtraction><type>Photo</type></imageExtraction>` | Teal (#008080)       |
| Drawing         | Image    | `<imageExtraction><type>Drawing</type></imageExtraction>` | Brown (#A52A2A)      |
| Other           | Image    | `<imageExtraction><type>Other</type></imageExtraction>` | Black (#000000)      |


## Libraries:
This is a list of third-party packages we used for this project. 
* [pdfrx](https://pub.dev/packages/pdfrx)
* [file_selector](https://pub.dev/packages/file_selector)
* [image](https://pub.dev/packages/image)

## Related Links:
* [pdfrx Demo Website](https://github.com/espresso3389/pdfrx/tree/master/packages/pdfrx/example/viewer)

