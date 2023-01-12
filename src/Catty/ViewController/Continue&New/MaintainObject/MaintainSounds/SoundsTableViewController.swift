/**
 *  Copyright (C) 2010-2022 The Catrobat Team
 *  (http://developer.catrobat.org/credits)
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as
 *  published by the Free Software Foundation, either version 3 of the
 *  License, or (at your option) any later version.
 *
 *  An additional term exception under section 7 of the GNU Affero
 *  General Public License, version 3, is available at
 *  (http://developer.catrobat.org/license_additional_term)
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see http://www.gnu.org/licenses/.
 */

import AudioKit
import Foundation

@objc(SoundDelegate)
protocol SoundDelegate: NSObjectProtocol {
    func showSaveSoundAlert(_ sound: Sound?)
    func addSound(_ sound: Sound?)
    func showDownloadSoundAlert(_ sound: Sound?)
}

@objc(SoundsTableViewController)
class SoundsTableViewController: BaseTableViewController, AVAudioPlayerDelegate, AudioManagerDelegate, SoundDelegate {

    private var useDetailCells = false
    private var currentPlayingSong: Sound?
    private var sound: Sound?
    private weak var currentPlayingSongCell: (UITableViewCell & CatrobatImageCell)?
    private var isAllowed = false
    private var deletionMode = false
    var audioEngine: AudioEngine!
@objc var object: SpriteObject?
@objc var showAddSoundActionSheetAtStart = false
@objc var afterSafeBlock: ((_ look: Sound?) -> Void)?

    func initNavigationBar() {
        let editButtonItem = TableUtil.editButtonItem(withTarget: self, action: #selector(editAction(_:)))
        navigationItem.rightBarButtonItem = editButtonItem
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        audioEngine = AudioEngine()
        audioEngine.start()
        let showDetails = UserDefaults.standard.object(forKey: kUserDetailsShowDetailsKey) as? [String: Any]
        let showDetailsSoundsValue = showDetails?[kUserDetailsShowDetailsSoundsKey] as? NSNumber
        useDetailCells = showDetailsSoundsValue?.boolValue ?? false
        navigationController?.title = kLocalizedSounds
        self.title = kLocalizedSounds
        initNavigationBar()
        changeEditingBarButtonState()
        currentPlayingSong = nil
        currentPlayingSongCell = nil
        self.placeHolderView.title = kLocalizedTapPlusToAddSound
        showPlaceHolder(!((object?.soundList.count)! > 0))
        setupToolBar()
        tableView.tableFooterView = UIView(frame: .zero)
        isAllowed = true

        if showAddSoundActionSheetAtStart {
            addSoundAction(nil)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: false)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        currentPlayingSongCell = nil
        stopAllSounds()
        audioEngine.stop()

    }

    @objc override func playSceneAction(_ sender: Any) {
        stopAllSounds()
        super.playSceneAction(sender)
    }

    @objc func editAction(_ sender: Any) {
        let actionSheet = AlertControllerBuilder.actionSheet(title: kLocalizedEditSounds)
            .addCancelAction(title: kLocalizedCancel, handler: nil)
        if object?.soundList.count ?? 0 > 0 {
            actionSheet.addDestructiveAction(title: kLocalizedDeleteSounds) {
                self.deletionMode = true
                self.setupEditingToolBar()
                super.changeToEditingMode(sender)
            }
        }
        if object?.soundList.count ?? 0 >= 2 {
            actionSheet.addDefaultAction(title: kLocalizedMoveSounds) {
                self.deletionMode = false
                super.changeToMoveMode(sender)
            }
        }
        let detailActionTitle = useDetailCells ? kLocalizedHideDetails : kLocalizedShowDetails
        actionSheet.addDefaultAction(title: detailActionTitle) {
            self.toggleDetailCellsMode()
        }
        actionSheet.build().showWithController(self)
    }

    func toggleDetailCellsMode() {
        useDetailCells = !useDetailCells
        let defaults = UserDefaults.standard
        let showDetails = defaults.object(forKey: kUserDetailsShowDetailsKey) as? [String: Any]
        var showDetailsMutable: [String: Any]
        if showDetails == nil {
            showDetailsMutable = [:]
        } else {
            showDetailsMutable = showDetails!
        }
        showDetailsMutable[kUserDetailsShowDetailsSoundsKey] = useDetailCells
        defaults.set(showDetailsMutable, forKey: kUserDetailsShowDetailsKey)
        defaults.synchronize()
        stopAllSounds()
        reloadData()
    }

    func addSoundToObjectAction(_ s: Sound) {
        var soundNames = [String]()
        for currentSound in object!.soundList {
          if let s = currentSound as? Sound {
            soundNames.append(s.name)
          }
        }
        s.name = Util.uniqueName(s.name, existingNames: soundNames)!
        let fileManager = CBFileManager.shared()
        guard let documentsDirectory = fileManager?.documentsDirectory else { return }
        let oldPath = "\(documentsDirectory)/\(s.fileName)"
        let data = NSData(contentsOfFile: oldPath)
        guard let fileExtension = s.fileName.components(separatedBy: ".").last else { return }
        s.fileName = "\( (data!.md5().replacingOccurrences(of: "-", with: "")).uppercased())\(kResourceFileNameSeparator)\(s.name).\(fileExtension)"
        print("Addsound obj filename: \n" + s.fileName)
        let newPath = s.path(for: object!.scene)
        if !checkIfSoundFolderExists() {
            fileManager?.createDirectory(object?.scene.soundsPath())
        }
        fileManager?.copyExistingFile(atPath: oldPath, toPath: newPath, overwrite: true)
        object?.soundList.add(s)
        let numberOfRowsInLastSection = tableView(tableView, numberOfRowsInSection: 0)
        showPlaceHolder(false)
        let indexPath = IndexPath(row: numberOfRowsInLastSection - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .none)
        object?.scene.project?.saveToDisk(withNotification: true)

        if let afterSafeBlock = afterSafeBlock {
            afterSafeBlock(sound)
        }
    }

    func checkIfSoundFolderExists() -> Bool {
        let manager = CBFileManager.shared()
        if manager?.directoryExists(object?.scene.soundsPath()) != nil {
            return true
        }
        return false
    }

    func copySoundAction(withSourceSound sourceSound: Sound) {
        showLoadingView()
        let nameOfCopiedSound = Util.uniqueName(sourceSound.name, existingNames: object?.allSoundNames())
        object?.copy(sourceSound, withNameForCopiedSound: nameOfCopiedSound, andSaveToDisk: true)
        let numberOfRowsInLastSection = tableView(tableView, numberOfRowsInSection: 0)
        let indexPath = IndexPath(row: numberOfRowsInLastSection - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .bottom)
        hideLoadingView()
    }

    func renameSoundAction(toName newSoundName: String, sound: Sound) {
        if newSoundName == sound.name {
            return
        }

        showLoadingView()
        let name = Util.uniqueName(newSoundName, existingNames: object?.allSoundNames())!
        object?.renameSound(sound, toName: name, andSaveToDisk: true)
        let soundIndex = (object?.soundList.index(of: sound))!
        let indexPath = IndexPath(row: soundIndex, section: 0)
        tableView.reloadRows(at: [indexPath], with: .none)
        hideLoadingView()
    }

    @objc func confirmDeleteSelectedSoundsAction(_ sender: Any?) {
        let selectedRowsIndexPaths = tableView.indexPathsForSelectedRows
        if (selectedRowsIndexPaths?.count ?? 0) == 0 {
            // nothing selected, nothing to delete...
            super.exitEditingMode()
            return
        }
        deletionMode = false
        deleteSelectedSoundsAction()
    }

    func deleteSelectedSoundsAction() {
        showLoadingView()
        stopAllSounds()
        let selectedRowsIndexPaths = tableView.indexPathsForSelectedRows!
        var soundsToRemove = [Sound]()
        for selectedRowIndexPath in selectedRowsIndexPaths {
            let sound = object?.soundList[selectedRowIndexPath.row] as! Sound
            soundsToRemove.append(sound)
        }
        object?.removeSounds(soundsToRemove, andSaveToDisk: true)
        super.exitEditingMode()
        tableView.deleteRows(at: selectedRowsIndexPaths, with: .none)
        super.showPlaceHolder((object?.soundList.count)! == 0)
        hideLoadingView()
        reloadData()
    }

    func deleteSound(for indexPath: IndexPath) {
        showLoadingView()
        stopAllSounds()
        let sound = object?.soundList[indexPath.row] as! Sound
        object?.remove(sound, andSaveToDisk: true)
        tableView.deleteRows(at: [indexPath], with: .none)
        super.showPlaceHolder(((object?.soundList.count)! == 0))
        hideLoadingView()
        reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (object?.soundList.count)!
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let CellIdentifier = kImageCell
        let DetailCellIdentifier = kDetailImageCell
        var cell: UITableViewCell
        if !useDetailCells {
            cell = tableView.dequeueReusableCell(withIdentifier: CellIdentifier, for: indexPath)
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: DetailCellIdentifier, for: indexPath)
        }

        let soundFromList = object?.soundList[indexPath.row] as? Sound
        if !(cell is CatrobatImageCell) || !(cell is CatrobatBaseCell) {
            return cell
        }
        let imageCell = cell as! CatrobatBaseCell & CatrobatImageCell
        imageCell.indexPath = indexPath
        let playIconName = "ic_media_play"
        let stopIconName = "ic_media_pause"

        // determine right icon, therefore check if this song is played currently
        var rightIconName = playIconName
        objc_sync_enter(self)
        if soundFromList!.playing && currentPlayingSong?.name == soundFromList?.name {
          rightIconName = stopIconName
        }

        objc_sync_exit(self)

        let imageCache = RuntimeImageCache.shared()
        if let image = imageCache?.cachedImage(forName: rightIconName) {
            imageCell.iconImageView.image = image
        } else {
            imageCache?.loadImage(withName: rightIconName) { img in
                // check if cell still needed
                if imageCell.indexPath == indexPath {
                    imageCell.iconImageView.image = img
                    imageCell.setNeedsLayout()
                }
            }
        }

        imageCell.titleLabel.text = soundFromList?.name
        imageCell.iconImageView.isUserInteractionEnabled = true
        let tapped = UITapGestureRecognizer(target: self, action: #selector(playSound(_:)))
        tapped.numberOfTapsRequired = 1
        imageCell.iconImageView.addGestureRecognizer(tapped)

        if useDetailCells, let detailCell = imageCell as? DarkBlueGradientImageDetailCell {
            detailCell.topLeftDetailLabel.textColor = UIColor.textTint
            detailCell.topLeftDetailLabel.text = "\(kLocalizedLength):"
            detailCell.topRightDetailLabel.textColor = UIColor.textTint

            let number = self.dataCache[soundFromList?.fileName as Any] as? NSNumber
            var duration: CGFloat
            if number == nil {
                duration = (self.object?.duration(of: sound))!
                self.dataCache[soundFromList?.fileName as Any] = NSNumber(value: duration)
            } else {
                duration = CGFloat(number!.floatValue)
            }

            detailCell.topRightDetailLabel.text = String(format: "%.02fs", duration)
            detailCell.bottomLeftDetailLabel.textColor = .textTint
            detailCell.bottomLeftDetailLabel.text = String(format: "%@:", kLocalizedSize)
            detailCell.bottomRightDetailLabel.textColor = .textTint
            let resultSize = (self.object?.fileSize(of: sound))!
            let sizeOfSound = NSNumber(value: resultSize)
            detailCell.bottomRightDetailLabel.text = ByteCountFormatter.string(fromByteCount: Int64(sizeOfSound.uintValue), countStyle: .binary)
            return detailCell
        }
        return imageCell
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        // INFO: NEVER REMOVE THIS EMPTY METHOD!!
        // This activates the swipe gesture handler for TableViewCells.
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        if self.deletionMode {
            return false
        }
        return true
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if self.isEditing {
            return .none
        }
        return .delete
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if !self.deletionMode {
            tableView.deselectRow(at: indexPath, animated: false)
            let cell = tableView.cellForRow(at: indexPath)!
            if cell is CatrobatImageCell {
                if indexPath.row >= (self.object?.soundList.count)! {
                    return
                }
                playSound(imageCell: cell as! (UITableViewCell & CatrobatImageCell), andIndexPath: indexPath)
            }
        }
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let itemToMove = self.object?.soundList[sourceIndexPath.row]
        self.object?.soundList.remove(sourceIndexPath.row)
        self.object?.soundList.insert(itemToMove as Any, at: destinationIndexPath.row)
        self.object?.scene.project?.saveToDisk(withNotification: false)
    }

    /*override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let moreAction = UIUtil.tableViewMoreRowAction(handler: { (action, indexPath) in
            // More button was pressed
            AlertControllerBuilder.actionSheet(title: kLocalizedEditSound)
                .addCancelAction(title: kLocalizedCancel, handler: nil)
                .addDefaultAction(title: kLocalizedCopy, handler: {
                    self.copySoundAction(withSourceSound: self.object?.soundList[indexPath.row] as! Sound)
                })
                .addDefaultAction(title: kLocalizedRename, handler: {
                    let soundFromList = self.object?.soundList[indexPath.row] as? Sound
                    Util.askUserForTextAndPerformAction(#selector(self.renameSoundActionToName(_:soundFromList:)), target: self, cancelAction: nil, withObject: sound, promptTitle: kLocalizedRenameSound, promptMessage: "\(kLocalizedSoundName):", promptValue: soundFromList?.name, promptPlaceholder: kLocalizedEnterYourSoundNameHere, minInputLength: UInt(kMinNumOfSoundNameCharacters), maxInputLength: UInt(kMaxNumOfSoundNameCharacters), invalidInputAlertMessage: kLocalizedInvalidSoundNameDescription)
                })
                .build()
                .viewWillDisappear({
                    self.tableView.setEditing(false, animated: true)
                })
                
        })
        moreAction.backgroundColor = UIColor.globalTint
        let deleteAction = UIUtil.tableViewDeleteRowAction(handler: { (action, indexPath) in
            // Delete button was pressed
            AlertControllerBuilder.alert(title: kLocalizedDeleteThisSound, message: kLocalizedThisActionCannotBeUndone)
                .addCancelAction(title: kLocalizedCancel, handler: nil)
                .addDefaultAction(title: kLocalizedYes, handler: {
                    self.deleteSound(for: indexPath)
                })
                .build()
                .show(withController: self)
        })
        return [deleteAction, moreAction]
    }.show(withController: self)*/

    @objc func playSound(_ sender: Any) {
        guard let gesture = sender as? UITapGestureRecognizer, gesture.view is UIImageView else { return }
        let imageView = gesture.view as! UIImageView
        let position = imageView.convert(CGPointZero, to: self.tableView)
        guard let indexPath = self.tableView.indexPathForRow(at: position), let cell = self.tableView.cellForRow(at: indexPath) as? CatrobatImageCell else { return }
        playSound(imageCell: cell as! (UITableViewCell & CatrobatImageCell), andIndexPath: indexPath)
    }

    func playSound(imageCell: UITableViewCell & CatrobatImageCell, andIndexPath indexPath: IndexPath) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        guard indexPath.row < (self.object?.soundList.count)! else { return }
        let soundFromList = self.object?.soundList[indexPath.row] as? Sound
        let isPlaying = soundFromList?.playing
        if let currentPlayingSong = self.currentPlayingSong, let currentPlayingSongCell = self.currentPlayingSongCell {
            currentPlayingSong.playing = false
            currentPlayingSongCell.iconImageView.image = UIImage(named: "ic_media_play")
        }
        self.currentPlayingSong = soundFromList
        self.currentPlayingSongCell = imageCell
        self.currentPlayingSong?.playing = !isPlaying!
        self.currentPlayingSongCell?.iconImageView.image = UIImage(named: "ic_media_play")
        if !isPlaying! {
            imageCell.iconImageView.image = UIImage(named: "ic_media_pause")
        }

        let queue = DispatchQueue(label: "at.tugraz.ist.catrobat.PlaySoundTVCQueue")
        queue.async {
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }
            AudioManager.shared().stopAllSounds()
            //self.audioEngine.stopAllAudioPlayers()
            if isPlaying! {
                return
            }
            //guard let fileName = soundFromList?.fileName else { return }
            //guard let dirPath = self.object?.scene.soundsPath() else { return }

            //self.audioEngine.playSound(fileName: fileName, key: (self.object?.name)!, filePath: dirPath, expectation: nil)

            guard let fileName = soundFromList?.fileName else { return }
            let am = AudioManager.shared()
            let isPlayable = am?.playSound(withFileName: fileName, andKey: (self.object?.name)!, atFilePath: self.object?.scene.soundsPath(), delegate: self)
            //if isPlayable! {
            //    return
            //}
            //DispatchQueue.main.sync {
            // Util.alert(text: kLocalizedUnableToPlaySoundDescription)
            // self.stopAllSounds()
            //}
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return TableUtil.heightForImageCell()
    }

    func audioItemDidFinishPlaying(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: notification.object)
        if (currentPlayingSong == nil) || (currentPlayingSongCell == nil) {
            return
        }

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        let tmpCurrentPlayingSong = self.currentPlayingSong
        let tmpCurrentPlayingSongCell = self.currentPlayingSongCell
        self.currentPlayingSong?.playing = false
        self.currentPlayingSong = nil
        self.currentPlayingSongCell = nil

        let playIconName = "ic_media_play"
        let imageCache = RuntimeImageCache.shared()
        let image = imageCache?.cachedImage(forName: playIconName)

        if image == nil {
            imageCache?.loadImage(withName: playIconName, onCompletion: { img in
                objc_sync_enter(self)
                defer { objc_sync_exit(self) }
                if (tmpCurrentPlayingSong != self.currentPlayingSong) && !(tmpCurrentPlayingSongCell === self.currentPlayingSongCell) {
                    tmpCurrentPlayingSongCell?.iconImageView.image = img
                }
            })
        } else {
            tmpCurrentPlayingSongCell?.iconImageView.image = image
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if (flag == false) || (currentPlayingSong == nil) || (currentPlayingSongCell == nil) {
            return
        }

        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        let currentPlayingSong = self.currentPlayingSong
        let currentPlayingSongCell = self.currentPlayingSongCell
        self.currentPlayingSong?.playing = false
        self.currentPlayingSong = nil
        self.currentPlayingSongCell = nil

        let playIconName = "ic_media_play"
        let imageCache = RuntimeImageCache.shared()
        var image = imageCache?.cachedImage(forName: playIconName)

        if image == nil {
            imageCache?.loadImage(withName: playIconName, onCompletion: { img in
                objc_sync_enter(self)
                defer { objc_sync_exit(self) }
                if (currentPlayingSong != self.currentPlayingSong) && !(currentPlayingSongCell === self.currentPlayingSongCell) {
                    currentPlayingSongCell?.iconImageView.image = img
                }
            })
        } else {
            currentPlayingSongCell?.iconImageView.image = image
        }
    }

    override func exitEditingMode() {
        super.exitEditingMode()
        deletionMode = false
    }

    // MARK: - Helper Methods

    func stopAllSounds() {
        AudioManager.shared().stopAllSounds()
        //audioEngine.stopAllAudioPlayers()
        if let currentPlayingSongCell = currentPlayingSongCell {
            currentPlayingSongCell.iconImageView.image = UIImage(named: "ic_media_play")
        }
        currentPlayingSong?.playing = false
        currentPlayingSong = nil
        self.currentPlayingSongCell = nil
    }

    @objc func addSoundAction(_ sender: Any?) {
        tableView.setEditing(false, animated: true)

        let alertController = AlertControllerBuilder.actionSheet(title: kLocalizedAddSound)
            .addCancelAction(title: kLocalizedCancel) { [weak self] in
                self?.afterSafeBlock?(nil)
            }
            .addDefaultAction(title: kLocalizedPocketCodeRecorder) { [weak self] in
                print("Recorder")
                let session = AVAudioSession.sharedInstance()
                if session.responds(to: #selector(AVAudioSession.requestRecordPermission(_:))) {
                    session.requestRecordPermission { granted in
                        if granted {
                            // Microphone enabled code
                            DispatchQueue.main.async {
                                self?.isAllowed = true
                                self?.stopAllSounds()
                                guard let soundRecorderViewController = self?.storyboard?.instantiateViewController(withIdentifier: kSoundRecorderViewControllerIdentifier) as? SRViewController
                                else { return }
                                soundRecorderViewController.delegate = self
                                self?.show(soundRecorderViewController, sender: self)
                            }
                        } else {
                            // Microphone disabled code
                            DispatchQueue.main.async {
                                self?.suggestToOpenSettingsApp(with: kLocalizedNoAccesToMicrophoneCheckSettingsDescription)
                            }
                        }
                    }
                }
            }
            .addDefaultAction(title: kLocalizedMediaLibrary) { [weak self] in
                self?.isAllowed = true
                DispatchQueue.main.async {
                    self?.showSoundsMediaLibrary()
                }
            }
            .addDefaultAction(title: kLocalizedSelectFile) { [weak self] in
                self?.isAllowed = true
                DispatchQueue.main.async {
                    self?.showSoundsSelectFile()
                }
            }
            .build()
        alertController.showWithController(self)
    }

    func suggestToOpenSettingsApp(with message: String) {
        let alertController = AlertControllerBuilder.alert(title: nil, message: message)
            .addCancelAction(title: kLocalizedCancel, handler: nil)
            .addDefaultAction(title: kLocalizedSettings) {
                print("Settings Action")
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
            }
            .build()
        alertController.showWithController(self)
    }

    override func setupToolBar() {
        super.setupToolBar()

        let add = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addSoundAction(_:)))
        let play = PlayButton(target: self, action: #selector(playSceneAction(_:)))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        toolbarItems = [flex, add, flex, flex, play, flex]
    }

    override func setupEditingToolBar() {
        super.setupEditingToolBar()

        let deleteButton = UIBarButtonItem(title: kLocalizedDelete, style: .plain, target: self, action: #selector(confirmDeleteSelectedSoundsAction(_:)))
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        toolbarItems = [selectAllRowsButtonItem, flex, deleteButton]
    }

    func changeEditingBarButtonState() {
        navigationItem.rightBarButtonItem?.isEnabled = (object?.soundList.count)! >= 1
    }

    func reloadData() {
        DispatchQueue.main.async {
            self.tableView.reloadData()
            self.changeEditingBarButtonState()
        }
    }

    func addSound(_ sound: Sound?) {
        if isAllowed {
            let recording = sound! as Sound
            let fileManager = FileManager.default
            guard let documentsDirectory = CBFileManager.shared()?.documentsDirectory else { return }
            let filePath = "\(documentsDirectory)/\(recording.fileName)"
            addSoundToObjectAction(recording)
            do {
                try fileManager.removeItem(atPath: filePath)
            } catch {
                print("-.-")
            }
            isAllowed = false
        }
        if let afterSafeBlock = afterSafeBlock {
            afterSafeBlock(nil)
        }
        reloadData()
    }

    func showDownloadSoundAlert(_ sound: Sound?) {
        self.sound = sound
        saveSound()
    }

    func showSaveSoundAlert(_ sound: Sound?) {
        self.sound = sound
        let alertController = AlertControllerBuilder.alert(title: kLocalizedSaveToPocketCode, message: kLocalizedPaintSaveChanges)
            .addCancelAction(title: kLocalizedCancel) {
                self.cancelPaintSave()
            }
            .addDefaultAction(title: kLocalizedYes) {
                self.saveSound()
            }
            .build()
        alertController.showWithController(self)
    }

    func saveSound() {
        if let sound = sound {
            addSound(sound)
        }

        if let afterSafeBlock = afterSafeBlock {
            afterSafeBlock(nil)
        }
    }

    func cancelPaintSave() {
        let fileManager = CBFileManager.shared()
        guard let documentsDirectory = fileManager?.documentsDirectory else { return }
        let filePath = "\(documentsDirectory)/\(self.sound!.fileName)"
        try? FileManager.default.removeItem(atPath: filePath)
        if let afterSafeBlock = afterSafeBlock {
            afterSafeBlock(nil)
        }
    }

}
