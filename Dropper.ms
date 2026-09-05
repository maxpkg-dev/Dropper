/*
    Dropper 1.0.0
    Drag archives, 3D files, and bitmap images into a compact 3ds Max toolbox.
*/

global dropperApp

struct DropperSettingsData (
    extractNextToArchive = true,
    customExtractFolder = "",
    customRarExecutable = "",
    showImporterDialogs = false,
    renameDuplicateNodes = true,
    renameDuplicateMaterials = true,
    createUniqueLayer = false,
    windowX = -1,
    windowY = -1
)

struct DropperSceneCandidateData (
    sourceFilePath,
    relativeFilePath,
    fileExtension,
    rendererTag = "other",
    versionLabel = "",
    isCompatible = true,
    warningMessage = "",
    errorMessage = ""
)

struct DropperRelinkResultData (
    availableCount = 0,
    relinkedCount = 0,
    ambiguousCount = 0,
    missingCount = 0,
    sharedCount = 0
)

struct DropperArchiveTaskData (
    sourceFilePath,
    targetFolderPath,
    depth = 0,
    isTopLevel = false
)

struct DropperArchiveProviderData (
    providerType,
    executablePath,
    displayName
)

struct DropperAppManager (
    versionContent = "1.0.0",
    entryFilePath = "",
    scriptFolderPath = "",
    iniFilePath = "",
    settingsData = undefined,
    mainForm = undefined,
    dropPanel = undefined,
    dropPanelImage = undefined,
    statusLabel = undefined,
    logButton = undefined,
    logBox = undefined,
    helpForm = undefined,
    settingsForm = undefined,
    settingsExtractNextCheck = undefined,
    settingsExtractFolderBox = undefined,
    settingsExtractBrowseButton = undefined,
    settingsRarExecutableBox = undefined,
    settingsImporterDialogsCheck = undefined,
    settingsRenameNodesCheck = undefined,
    settingsRenameMaterialsCheck = undefined,
    settingsUniqueLayerCheck = undefined,
    deferredDropTimer = undefined,
    deferredDropFilePaths = #(),
    isLogVisible = false,
    highestSeverity = 0,
    warningCount = 0,
    errorCount = 0,
    isBusy = false,
    isCancelRequested = false,

    fn normalizeFolderPath folderPath = (
        if (folderPath == undefined or folderPath == "") do return ""
        local normalizedFolderPath = substituteString (folderPath as string) "/" "\\"
        if (normalizedFolderPath[normalizedFolderPath.count] != "\\") do normalizedFolderPath += "\\"
        return normalizedFolderPath
    ),

    fn readBooleanSetting iniSectionName settingKey defaultState = (
        local settingContent = getINISetting iniFilePath iniSectionName settingKey
        if (settingContent == "") do return defaultState
        return (toLower settingContent == "true")
    ),

    fn readIntegerSetting iniSectionName settingKey defaultNumber = (
        local settingContent = getINISetting iniFilePath iniSectionName settingKey
        if (settingContent == "") do return defaultNumber
        local parsedNumber = defaultNumber
        try (parsedNumber = settingContent as integer) catch (parsedNumber = defaultNumber)
        return parsedNumber
    ),

    fn themeBackgroundColor = (return (dotNetClass "System.Drawing.Color").FromArgb 15 4 35),
    fn themeSurfaceColor = (return (dotNetClass "System.Drawing.Color").FromArgb 34 12 61),
    fn themeInputColor = (return (dotNetClass "System.Drawing.Color").FromArgb 25 8 48),
    fn themeInputBorderColor = (return (dotNetClass "System.Drawing.Color").FromArgb 111 35 126),
    fn themeAccentColor = (return (dotNetClass "System.Drawing.Color").FromArgb 224 48 211),
    fn themeTextColor = (return (dotNetClass "System.Drawing.Color").FromArgb 246 229 255),
    fn themeMutedTextColor = (return (dotNetClass "System.Drawing.Color").FromArgb 203 158 225),

    fn applyFormTheme formControl = (
        formControl.BackColor = themeBackgroundColor()
        formControl.ForeColor = themeTextColor()
        return true
    ),

    fn applyButtonTheme buttonControl accentButton:false = (
        buttonControl.UseVisualStyleBackColor = false
        buttonControl.FlatStyle = (dotNetClass "System.Windows.Forms.FlatStyle").Flat
        buttonControl.FlatAppearance.BorderSize = 1
        buttonControl.FlatAppearance.BorderColor = themeAccentColor()
        buttonControl.BackColor = if accentButton then themeAccentColor() else themeSurfaceColor()
        buttonControl.ForeColor = themeTextColor()
        return true
    ),

    fn applyGroupTheme groupControl = (
        groupControl.BackColor = themeBackgroundColor()
        groupControl.ForeColor = themeMutedTextColor()
        return true
    ),

    fn applyTextInputTheme textControl = (
        textControl.BackColor = themeInputColor()
        textControl.ForeColor = themeTextColor()
        textControl.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").FixedSingle
        textControl.Multiline = true
        return true
    ),

    fn applyCheckBoxTheme checkControl = (
        checkControl.UseVisualStyleBackColor = true
        checkControl.Appearance = (dotNetClass "System.Windows.Forms.Appearance").Normal
        checkControl.FlatStyle = (dotNetClass "System.Windows.Forms.FlatStyle").Standard
        checkControl.TextAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleLeft
        checkControl.Padding = dotNetObject "System.Windows.Forms.Padding" 0
        checkControl.BackColor = themeBackgroundColor()
        checkControl.ForeColor = themeTextColor()
        return true
    ),

    fn onThemedCheckStateChanged senderObject eventArgs = (
        senderObject.BackColor = themeBackgroundColor()
        senderObject.Invalidate()
        return true
    ),

    fn applyLinkTheme linkControl = (
        linkControl.LinkColor = (dotNetClass "System.Drawing.Color").FromArgb 241 86 220
        linkControl.ActiveLinkColor = (dotNetClass "System.Drawing.Color").FromArgb 255 155 235
        linkControl.VisitedLinkColor = (dotNetClass "System.Drawing.Color").FromArgb 190 112 225
        return true
    ),

    fn readPackageVersionFromIni sourceIniFile sectionName settingKey = (
        if (not (dotNetClass "System.IO.File").Exists sourceIniFile) do return ""
        local resolvedVersion = ""
        try (resolvedVersion = trimString (getINISetting sourceIniFile sectionName settingKey)) catch (resolvedVersion = "")
        return resolvedVersion
    ),

    fn resolvePackageVersion = (
        local resolvedVersion = readPackageVersionFromIni (scriptFolderPath + "manifest.ini") "package" "version"
        if (resolvedVersion == "") do (
            resolvedVersion = readPackageVersionFromIni (scriptFolderPath + "maxpkg-packager.ini") "settings" "version"
        )
        if (resolvedVersion == "") do resolvedVersion = "1.0.0"
        return resolvedVersion
    ),

    fn createGuidString = (
        local guidClass = dotNetClass "System.Guid"
        local guidInstance = guidClass.NewGuid()
        return (guidInstance.ToString "N")
    ),

    fn canWriteSettingsFolder = (
        local probeFilePath = scriptFolderPath + ".dropper-write-probe-" + createGuidString() + ".tmp"
        local isWritable = false
        try (
            (dotNetClass "System.IO.File").WriteAllText probeFilePath "Dropper"
            isWritable = (dotNetClass "System.IO.File").Exists probeFilePath
        ) catch (
            isWritable = false
        )
        try (
            if ((dotNetClass "System.IO.File").Exists probeFilePath) do (
                (dotNetClass "System.IO.File").Delete probeFilePath
            )
        ) catch()
        return isWritable
    ),

    fn loadSettings = (
        settingsData = DropperSettingsData()
        if ((dotNetClass "System.IO.File").Exists iniFilePath) do (
            settingsData.extractNextToArchive = readBooleanSetting "Archive" "ExtractNextToArchive" true
            settingsData.customExtractFolder = getINISetting iniFilePath "Archive" "CustomExtractFolder"
            settingsData.customRarExecutable = getINISetting iniFilePath "Archive" "CustomRarExecutable"
            settingsData.showImporterDialogs = readBooleanSetting "Import" "ShowImporterDialogs" false
            settingsData.renameDuplicateNodes = readBooleanSetting "SafeMerge" "RenameDuplicateNodes" true
            settingsData.renameDuplicateMaterials = readBooleanSetting "SafeMerge" "RenameDuplicateMaterials" true
            settingsData.createUniqueLayer = readBooleanSetting "SafeMerge" "CreateUniqueLayer" false
            settingsData.windowX = readIntegerSetting "Window" "X" -1
            settingsData.windowY = readIntegerSetting "Window" "Y" -1
        )
        return settingsData
    ),

    fn saveSettings = (
        if (settingsData == undefined) do return false
        if (not canWriteSettingsFolder()) do return false

        local temporaryIniPath = scriptFolderPath + ".Dropper-" + createGuidString() + ".ini"
        try (
            if ((dotNetClass "System.IO.File").Exists iniFilePath) do (
                (dotNetClass "System.IO.File").Copy iniFilePath temporaryIniPath true
            )
            setINISetting temporaryIniPath "Archive" "ExtractNextToArchive" (settingsData.extractNextToArchive as string)
            setINISetting temporaryIniPath "Archive" "CustomExtractFolder" settingsData.customExtractFolder
            setINISetting temporaryIniPath "Archive" "CustomRarExecutable" settingsData.customRarExecutable
            setINISetting temporaryIniPath "Import" "ShowImporterDialogs" (settingsData.showImporterDialogs as string)
            setINISetting temporaryIniPath "SafeMerge" "RenameDuplicateNodes" (settingsData.renameDuplicateNodes as string)
            setINISetting temporaryIniPath "SafeMerge" "RenameDuplicateMaterials" (settingsData.renameDuplicateMaterials as string)
            setINISetting temporaryIniPath "SafeMerge" "CreateUniqueLayer" (settingsData.createUniqueLayer as string)
            setINISetting temporaryIniPath "Window" "X" (settingsData.windowX as string)
            setINISetting temporaryIniPath "Window" "Y" (settingsData.windowY as string)
            (dotNetClass "System.IO.File").Copy temporaryIniPath iniFilePath true
            (dotNetClass "System.IO.File").Delete temporaryIniPath
        ) catch (
            try (
                if ((dotNetClass "System.IO.File").Exists temporaryIniPath) do (
                    (dotNetClass "System.IO.File").Delete temporaryIniPath
                )
            ) catch()
            return false
        )
        return true
    ),

    fn getLogColor severityLevel = (
        local colorClass = dotNetClass "System.Drawing.Color"
        case severityLevel of (
            1: return (colorClass.FromArgb 80 190 110)
            2: return (colorClass.FromArgb 235 165 55)
            3: return (colorClass.FromArgb 230 80 80)
            default: return themeTextColor()
        )
    ),

    fn updateLogButton = (
        if (logButton == undefined) do return false
        local buttonCaption = if isLogVisible then "Hide Log" else "Show Log"
        if (warningCount > 0 or errorCount > 0) do (
            buttonCaption += " (" + (warningCount as string) + "/" + (errorCount as string) + ")"
        )
        logButton.Text = buttonCaption
        logButton.ForeColor = getLogColor highestSeverity
        return true
    ),

    fn addLog messageContent severityLevel:0 = (
        local severityPrefix = case severityLevel of (
            1: "[SUCCESS] "
            2: "[WARNING] "
            3: "[ERROR] "
            default: "[INFO] "
        )
        if (severityLevel == 2) do warningCount += 1
        if (severityLevel == 3) do errorCount += 1
        if (severityLevel > highestSeverity) do highestSeverity = severityLevel
        if (logBox != undefined) do (
            logBox.SelectionStart = logBox.TextLength
            logBox.SelectionLength = 0
            logBox.SelectionColor = getLogColor severityLevel
            logBox.AppendText (severityPrefix + messageContent + "\r\n")
            logBox.SelectionStart = logBox.TextLength
            logBox.ScrollToCaret()
        )
        updateLogButton()
        return true
    ),

    fn setStatus messageContent = (
        if (statusLabel != undefined) do statusLabel.Text = messageContent
        return true
    ),

    fn isMainFormVisible = (
        if (mainForm == undefined) do return false
        try (return (not mainForm.IsDisposed and mainForm.Visible)) catch (return false)
    ),

    fn restoreWindowPosition = (
        local screenClass = dotNetClass "System.Windows.Forms.Screen"
        local desiredX = settingsData.windowX
        local desiredY = settingsData.windowY
        local candidateRectangle = dotNetObject "System.Drawing.Rectangle" desiredX desiredY mainForm.Width mainForm.Height
        local isOnScreen = false
        for screenInfo in screenClass.AllScreens while (not isOnScreen) do (
            if (screenInfo.WorkingArea.IntersectsWith candidateRectangle) do isOnScreen = true
        )
        mainForm.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").Manual
        if (desiredX >= 0 and desiredY >= 0 and isOnScreen) then (
            mainForm.Location = dotNetObject "System.Drawing.Point" desiredX desiredY
        ) else (
            local primaryArea = screenClass.PrimaryScreen.WorkingArea
            mainForm.Location = dotNetObject "System.Drawing.Point" (primaryArea.Left + 40) (primaryArea.Top + 80)
        )
        return true
    ),

    fn rememberWindowPosition = (
        if (mainForm == undefined or settingsData == undefined) do return false
        try (
            if (mainForm.WindowState == (dotNetClass "System.Windows.Forms.FormWindowState").Normal) do (
                settingsData.windowX = mainForm.Left
                settingsData.windowY = mainForm.Top
            )
        ) catch()
        return saveSettings()
    ),

    fn toggleLog = (
        if (mainForm == undefined or logBox == undefined) do return false
        isLogVisible = not isLogVisible
        logBox.Visible = isLogVisible
        mainForm.ClientSize = dotNetObject "System.Drawing.Size" 330 (if isLogVisible then 440 else 160)
        updateLogButton()
        return true
    ),

    fn onToggleLog senderObject eventArgs = (
        toggleLog()
    ),

    fn onDropPanelDragEnter senderObject dragEventArgs = (
        local dataFormatsClass = dotNetClass "System.Windows.Forms.DataFormats"
        if (dragEventArgs.Data.GetDataPresent dataFormatsClass.FileDrop) then (
            dragEventArgs.Effect = (dotNetClass "System.Windows.Forms.DragDropEffects").Copy
        ) else (
            dragEventArgs.Effect = (dotNetClass "System.Windows.Forms.DragDropEffects").None
        )
    ),

    fn onMainFormClosing senderObject formClosingArgs = (
        rememberWindowPosition()
        isCancelRequested = true
        if (deferredDropTimer != undefined) do (
            try (deferredDropTimer.Stop()) catch()
            try (deferredDropTimer.Dispose()) catch()
            deferredDropTimer = undefined
            deferredDropFilePaths = #()
        )
        if (helpForm != undefined) do try (helpForm.Close()) catch()
        if (settingsForm != undefined) do try (settingsForm.Close()) catch()
        if (dropPanelImage != undefined) do (
            try (dropPanelImage.Dispose()) catch()
            dropPanelImage = undefined
        )
        enableAccelerators = true
    ),

    fn openWebAddress webAddress = (		
		ShellLaunch webAddress ""		
        return true
    ),

    fn onOpen3DGround senderObject eventArgs = (return openWebAddress "https://3dground.net"),
    fn onOpenMaxPkg senderObject eventArgs = (return openWebAddress "https://maxpkg.dev"),
    fn onDonate senderObject eventArgs = (return openWebAddress "https://store.payproglobal.com/checkout?products[1][id]=137852"),

    fn onHelpFormClosed senderObject eventArgs = (
        helpForm = undefined
        return true
    ),

    fn showHelpForm = (
        if (helpForm != undefined) do (
            try (
                if (not helpForm.IsDisposed and helpForm.Visible) do (
                    helpForm.Activate()
                    return true
                )
                if (not helpForm.IsDisposed) do helpForm.Dispose()
            ) catch()
            helpForm = undefined
        )

        helpForm = dotNetObject "System.Windows.Forms.Form"
        helpForm.Text = "What Dropper can do"
        helpForm.FormBorderStyle = (dotNetClass "System.Windows.Forms.FormBorderStyle").FixedToolWindow
        helpForm.ClientSize = dotNetObject "System.Drawing.Size" 460 382
        helpForm.MaximizeBox = false
        helpForm.MinimizeBox = false
        helpForm.ShowInTaskbar = false
        helpForm.TopMost = true
        helpForm.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").CenterScreen
        applyFormTheme helpForm

        local helpTextBox = dotNetObject "System.Windows.Forms.RichTextBox"
        helpTextBox.Location = dotNetObject "System.Drawing.Point" 14 14
        helpTextBox.Size = dotNetObject "System.Drawing.Size" 432 294
        helpTextBox.ReadOnly = true
        helpTextBox.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").None
        helpTextBox.BackColor = themeBackgroundColor()
        helpTextBox.ForeColor = themeTextColor()
        helpTextBox.ScrollBars = (dotNetClass "System.Windows.Forms.RichTextBoxScrollBars").Vertical
        helpTextBox.DetectUrls = false
        helpTextBox.TabStop = false
        helpTextBox.Rtf = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Segoe UI;}}\\fs18 \\b Drag and drop files into Dropper\\b0\\par \\par \\b Archives (.zip, .rar, .7z)\\b0\\par \\tab - Unpacks the archive into a folder.\\par \\tab - Finds a suitable 3D model inside.\\par \\tab - Imports the model into the current scene.\\par \\tab - Relinks textures when possible.\\par \\par \\b 3D models (.max, .fbx, .obj and others)\\b0\\par \\tab - Imports or merges the model.\\par \\tab - Places imported objects on the floor.\\par \\tab - Handles duplicate names safely.\\par \\tab - Reconnects nearby texture files.\\par \\par \\b Reference images\\b0\\par \\tab - Creates one image plane for each picture.\\par \\tab - Keeps the original image proportions.\\par \\tab - Places the pictures next to each other.\\par}"
        helpTextBox.SelectAll()
        helpTextBox.SelectionColor = themeTextColor()
        helpTextBox.Select 0 0
        helpForm.Controls.Add helpTextBox

        local helpGroundLink = dotNetObject "System.Windows.Forms.LinkLabel"
        helpGroundLink.Text = "3dground.net"
        helpGroundLink.Location = dotNetObject "System.Drawing.Point" 14 336
        helpGroundLink.Size = dotNetObject "System.Drawing.Size" 105 20
        applyLinkTheme helpGroundLink
        helpForm.Controls.Add helpGroundLink

        local helpMaxPkgLink = dotNetObject "System.Windows.Forms.LinkLabel"
        helpMaxPkgLink.Text = "maxpkg.dev"
        helpMaxPkgLink.Location = dotNetObject "System.Drawing.Point" 126 336
        helpMaxPkgLink.Size = dotNetObject "System.Drawing.Size" 100 20
        applyLinkTheme helpMaxPkgLink
        helpForm.Controls.Add helpMaxPkgLink

        local helpDonateButton = dotNetObject "System.Windows.Forms.Button"
        helpDonateButton.Text = "Donate"
        helpDonateButton.Location = dotNetObject "System.Drawing.Point" 336 328
        helpDonateButton.Size = dotNetObject "System.Drawing.Size" 110 34
        applyButtonTheme helpDonateButton accentButton:true
        helpForm.Controls.Add helpDonateButton

        dotNet.addEventHandler helpGroundLink "Click" onOpen3DGround
        dotNet.addEventHandler helpMaxPkgLink "Click" onOpenMaxPkg
        dotNet.addEventHandler helpDonateButton "Click" onDonate
        dotNet.addEventHandler helpForm "FormClosed" onHelpFormClosed
        helpForm.Show mainForm
        return true
    ),

    fn onHelpButtonClick senderObject eventArgs = (
        return showHelpForm()
    ),

    fn saveSettingsFromControls = (
        if (settingsData == undefined or settingsExtractNextCheck == undefined) do return false
        settingsData.extractNextToArchive = settingsExtractNextCheck.Checked
        settingsData.customExtractFolder = settingsExtractFolderBox.Text
        settingsData.customRarExecutable = settingsRarExecutableBox.Text
        settingsData.showImporterDialogs = settingsImporterDialogsCheck.Checked
        settingsData.renameDuplicateNodes = settingsRenameNodesCheck.Checked
        settingsData.renameDuplicateMaterials = settingsRenameMaterialsCheck.Checked
        settingsData.createUniqueLayer = settingsUniqueLayerCheck.Checked
        if (not saveSettings()) do (
            messageBox ("Dropper could not save settings next to:\n" + entryFilePath) title:"Dropper"
            return false
        )
        return true
    ),

    fn onSettingsSameFolderChanged senderObject eventArgs = (
        local areCustomFolderControlsEnabled = not settingsExtractNextCheck.Checked
        settingsExtractFolderBox.ReadOnly = not areCustomFolderControlsEnabled
        settingsExtractFolderBox.BackColor = if areCustomFolderControlsEnabled then themeInputColor() else themeSurfaceColor()
        settingsExtractBrowseButton.Enabled = areCustomFolderControlsEnabled
        return saveSettingsFromControls()
    ),

    fn onSettingsValueChanged senderObject eventArgs = (
        return saveSettingsFromControls()
    ),

    fn onSettingsTextLeave senderObject eventArgs = (
        return saveSettingsFromControls()
    ),

    fn chooseFolderWithExplorerDialog initialFolderPath = (
        local folderDialog = dotNetObject "System.Windows.Forms.OpenFileDialog"
        folderDialog.Title = "Choose the archive extraction folder"
        folderDialog.Filter = "Folders|*.folder"
        folderDialog.FileName = "Select this folder"
        folderDialog.AddExtension = false
        folderDialog.CheckFileExists = false
        folderDialog.CheckPathExists = true
        folderDialog.ValidateNames = false
        folderDialog.DereferenceLinks = true
        if (initialFolderPath != "" and (dotNetClass "System.IO.Directory").Exists initialFolderPath) do (
            folderDialog.InitialDirectory = initialFolderPath
        )
        if (folderDialog.ShowDialog settingsForm != (dotNetClass "System.Windows.Forms.DialogResult").OK) do return undefined

        local selectedFilePath = folderDialog.FileName
        if ((dotNetClass "System.IO.Directory").Exists selectedFilePath) do return selectedFilePath
        return (dotNetClass "System.IO.Path").GetDirectoryName selectedFilePath
    ),

    fn onSettingsBrowseExtract senderObject eventArgs = (
        local selectedFolderPath = chooseFolderWithExplorerDialog settingsExtractFolderBox.Text
        if (selectedFolderPath != undefined and selectedFolderPath != "") do (
            settingsExtractFolderBox.Text = selectedFolderPath
            return saveSettingsFromControls()
        )
        return true
    ),

    fn onSettingsBrowseRar senderObject eventArgs = (
        local fileDialog = dotNetObject "System.Windows.Forms.OpenFileDialog"
        fileDialog.Title = "Choose a RAR-compatible executable"
        fileDialog.Filter = "Executables|*.exe|All files|*.*"
        if (fileDialog.ShowDialog() == (dotNetClass "System.Windows.Forms.DialogResult").OK) do (
            settingsRarExecutableBox.Text = fileDialog.FileName
            return saveSettingsFromControls()
        )
        return true
    ),

    fn onSettingsFormClosed senderObject eventArgs = (
        settingsForm = undefined
        enableAccelerators = true
        return true
    ),

    fn addSettingsLabel parentControl captionContent xPosition yPosition controlWidth = (
        local labelControl = dotNetObject "System.Windows.Forms.Label"
        labelControl.Text = captionContent
        labelControl.Location = dotNetObject "System.Drawing.Point" xPosition yPosition
        labelControl.Size = dotNetObject "System.Drawing.Size" controlWidth 18
        labelControl.ForeColor = themeTextColor()
        parentControl.Controls.Add labelControl
        return labelControl
    ),

    fn showSettingsForm = (
        if (settingsForm != undefined) do (
            try (
                if (not settingsForm.IsDisposed and settingsForm.Visible) do (
                    settingsForm.Activate()
                    return true
                )
                if (not settingsForm.IsDisposed) do settingsForm.Dispose()
            ) catch()
            settingsForm = undefined
        )

        settingsForm = dotNetObject "System.Windows.Forms.Form"
        settingsForm.Text = "Dropper Settings"
        settingsForm.FormBorderStyle = (dotNetClass "System.Windows.Forms.FormBorderStyle").FixedToolWindow
        settingsForm.ClientSize = dotNetObject "System.Drawing.Size" 420 506
        settingsForm.MaximizeBox = false
        settingsForm.MinimizeBox = false
        settingsForm.ShowInTaskbar = false
        settingsForm.TopMost = true
        settingsForm.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").CenterScreen
        applyFormTheme settingsForm

        local archiveGroup = dotNetObject "System.Windows.Forms.GroupBox"
        archiveGroup.Text = "Archive extraction"
        archiveGroup.Location = dotNetObject "System.Drawing.Point" 10 10
        archiveGroup.Size = dotNetObject "System.Drawing.Size" 400 150
        applyGroupTheme archiveGroup
        settingsForm.Controls.Add archiveGroup

        settingsExtractNextCheck = dotNetObject "System.Windows.Forms.CheckBox"
        settingsExtractNextCheck.Text = "Extract next to archive"
        settingsExtractNextCheck.Location = dotNetObject "System.Drawing.Point" 12 22
        settingsExtractNextCheck.Size = dotNetObject "System.Drawing.Size" 260 24
        settingsExtractNextCheck.Checked = settingsData.extractNextToArchive
        applyCheckBoxTheme settingsExtractNextCheck
        archiveGroup.Controls.Add settingsExtractNextCheck

        addSettingsLabel archiveGroup "Custom extraction folder" 12 48 250
        local extractFolderBorder = dotNetObject "System.Windows.Forms.Panel"
        extractFolderBorder.Location = dotNetObject "System.Drawing.Point" 12 68
        extractFolderBorder.Size = dotNetObject "System.Drawing.Size" 330 24
        extractFolderBorder.BackColor = themeInputBorderColor()
        archiveGroup.Controls.Add extractFolderBorder
        settingsExtractFolderBox = dotNetObject "System.Windows.Forms.TextBox"
        settingsExtractFolderBox.Location = dotNetObject "System.Drawing.Point" 1 1
        settingsExtractFolderBox.Size = dotNetObject "System.Drawing.Size" 328 22
        settingsExtractFolderBox.Text = settingsData.customExtractFolder
        settingsExtractFolderBox.ReadOnly = settingsData.extractNextToArchive
        applyTextInputTheme settingsExtractFolderBox
        settingsExtractFolderBox.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").None
        if (settingsExtractFolderBox.ReadOnly) do settingsExtractFolderBox.BackColor = themeSurfaceColor()
        extractFolderBorder.Controls.Add settingsExtractFolderBox

        settingsExtractBrowseButton = dotNetObject "System.Windows.Forms.Button"
        settingsExtractBrowseButton.Text = "..."
        settingsExtractBrowseButton.Location = dotNetObject "System.Drawing.Point" 348 68
        settingsExtractBrowseButton.Size = dotNetObject "System.Drawing.Size" 40 24
        settingsExtractBrowseButton.Enabled = not settingsData.extractNextToArchive
        applyButtonTheme settingsExtractBrowseButton
        archiveGroup.Controls.Add settingsExtractBrowseButton

        addSettingsLabel archiveGroup "RAR-compatible executable (optional)" 12 95 300
        local rarExecutableBorder = dotNetObject "System.Windows.Forms.Panel"
        rarExecutableBorder.Location = dotNetObject "System.Drawing.Point" 12 115
        rarExecutableBorder.Size = dotNetObject "System.Drawing.Size" 330 24
        rarExecutableBorder.BackColor = themeInputBorderColor()
        archiveGroup.Controls.Add rarExecutableBorder
        settingsRarExecutableBox = dotNetObject "System.Windows.Forms.TextBox"
        settingsRarExecutableBox.Location = dotNetObject "System.Drawing.Point" 1 1
        settingsRarExecutableBox.Size = dotNetObject "System.Drawing.Size" 328 22
        settingsRarExecutableBox.Text = settingsData.customRarExecutable
        applyTextInputTheme settingsRarExecutableBox
        settingsRarExecutableBox.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").None
        rarExecutableBorder.Controls.Add settingsRarExecutableBox

        local browseRarButton = dotNetObject "System.Windows.Forms.Button"
        browseRarButton.Text = "..."
        browseRarButton.Location = dotNetObject "System.Drawing.Point" 348 115
        browseRarButton.Size = dotNetObject "System.Drawing.Size" 40 24
        applyButtonTheme browseRarButton
        archiveGroup.Controls.Add browseRarButton

        local importGroup = dotNetObject "System.Windows.Forms.GroupBox"
        importGroup.Text = "Import"
        importGroup.Location = dotNetObject "System.Drawing.Point" 10 168
        importGroup.Size = dotNetObject "System.Drawing.Size" 400 58
        applyGroupTheme importGroup
        settingsForm.Controls.Add importGroup

        settingsImporterDialogsCheck = dotNetObject "System.Windows.Forms.CheckBox"
        settingsImporterDialogsCheck.Text = "Show native importer dialogs"
        settingsImporterDialogsCheck.Location = dotNetObject "System.Drawing.Point" 12 22
        settingsImporterDialogsCheck.Size = dotNetObject "System.Drawing.Size" 300 24
        settingsImporterDialogsCheck.Checked = settingsData.showImporterDialogs
        applyCheckBoxTheme settingsImporterDialogsCheck
        importGroup.Controls.Add settingsImporterDialogsCheck

        local safeMergeGroup = dotNetObject "System.Windows.Forms.GroupBox"
        safeMergeGroup.Text = "Safe merge"
        safeMergeGroup.Location = dotNetObject "System.Drawing.Point" 10 234
        safeMergeGroup.Size = dotNetObject "System.Drawing.Size" 400 102
        applyGroupTheme safeMergeGroup
        settingsForm.Controls.Add safeMergeGroup

        settingsRenameNodesCheck = dotNetObject "System.Windows.Forms.CheckBox"
        settingsRenameNodesCheck.Text = "Rename incoming duplicate nodes"
        settingsRenameNodesCheck.Location = dotNetObject "System.Drawing.Point" 12 20
        settingsRenameNodesCheck.Size = dotNetObject "System.Drawing.Size" 330 24
        settingsRenameNodesCheck.Checked = settingsData.renameDuplicateNodes
        applyCheckBoxTheme settingsRenameNodesCheck
        safeMergeGroup.Controls.Add settingsRenameNodesCheck

        settingsRenameMaterialsCheck = dotNetObject "System.Windows.Forms.CheckBox"
        settingsRenameMaterialsCheck.Text = "Rename incoming duplicate materials"
        settingsRenameMaterialsCheck.Location = dotNetObject "System.Drawing.Point" 12 46
        settingsRenameMaterialsCheck.Size = dotNetObject "System.Drawing.Size" 350 24
        settingsRenameMaterialsCheck.Checked = settingsData.renameDuplicateMaterials
        applyCheckBoxTheme settingsRenameMaterialsCheck
        safeMergeGroup.Controls.Add settingsRenameMaterialsCheck

        settingsUniqueLayerCheck = dotNetObject "System.Windows.Forms.CheckBox"
        settingsUniqueLayerCheck.Text = "Create a unique import layer"
        settingsUniqueLayerCheck.Location = dotNetObject "System.Drawing.Point" 12 72
        settingsUniqueLayerCheck.Size = dotNetObject "System.Drawing.Size" 300 24
        settingsUniqueLayerCheck.Checked = settingsData.createUniqueLayer
        applyCheckBoxTheme settingsUniqueLayerCheck
        safeMergeGroup.Controls.Add settingsUniqueLayerCheck

        local aboutGroup = dotNetObject "System.Windows.Forms.GroupBox"
        aboutGroup.Text = "About"
        aboutGroup.Location = dotNetObject "System.Drawing.Point" 10 344
        aboutGroup.Size = dotNetObject "System.Drawing.Size" 400 152
        applyGroupTheme aboutGroup
        settingsForm.Controls.Add aboutGroup

        local productLabel = addSettingsLabel aboutGroup "Dropper" 12 22 190
        productLabel.Font = dotNetObject "System.Drawing.Font" productLabel.Font (dotNetClass "System.Drawing.FontStyle").Bold
        addSettingsLabel aboutGroup "Lukianenko Vasyl" 12 48 190
        addSettingsLabel aboutGroup versionContent 12 72 190

        local groundLink = dotNetObject "System.Windows.Forms.LinkLabel"
        groundLink.Text = "3dground.net"
        groundLink.Location = dotNetObject "System.Drawing.Point" 220 24
        groundLink.Size = dotNetObject "System.Drawing.Size" 165 20
        applyLinkTheme groundLink
        aboutGroup.Controls.Add groundLink

        local maxPkgLink = dotNetObject "System.Windows.Forms.LinkLabel"
        maxPkgLink.Text = "maxpkg.dev"
        maxPkgLink.Location = dotNetObject "System.Drawing.Point" 220 50
        maxPkgLink.Size = dotNetObject "System.Drawing.Size" 165 20
        applyLinkTheme maxPkgLink
        aboutGroup.Controls.Add maxPkgLink

        local donateButton = dotNetObject "System.Windows.Forms.Button"
        donateButton.Text = "Donate"
        donateButton.Location = dotNetObject "System.Drawing.Point" 278 96
        donateButton.Size = dotNetObject "System.Drawing.Size" 110 34
        applyButtonTheme donateButton accentButton:true
        aboutGroup.Controls.Add donateButton

        dotNet.addEventHandler settingsExtractNextCheck "CheckedChanged" onSettingsSameFolderChanged
        dotNet.addEventHandler settingsExtractNextCheck "CheckedChanged" onThemedCheckStateChanged
        dotNet.addEventHandler settingsExtractFolderBox "Leave" onSettingsTextLeave
        dotNet.addEventHandler settingsRarExecutableBox "Leave" onSettingsTextLeave
        dotNet.addEventHandler settingsImporterDialogsCheck "CheckedChanged" onSettingsValueChanged
        dotNet.addEventHandler settingsImporterDialogsCheck "CheckedChanged" onThemedCheckStateChanged
        dotNet.addEventHandler settingsRenameNodesCheck "CheckedChanged" onSettingsValueChanged
        dotNet.addEventHandler settingsRenameNodesCheck "CheckedChanged" onThemedCheckStateChanged
        dotNet.addEventHandler settingsRenameMaterialsCheck "CheckedChanged" onSettingsValueChanged
        dotNet.addEventHandler settingsRenameMaterialsCheck "CheckedChanged" onThemedCheckStateChanged
        dotNet.addEventHandler settingsUniqueLayerCheck "CheckedChanged" onSettingsValueChanged
        dotNet.addEventHandler settingsUniqueLayerCheck "CheckedChanged" onThemedCheckStateChanged
        dotNet.addEventHandler settingsExtractBrowseButton "Click" onSettingsBrowseExtract
        dotNet.addEventHandler browseRarButton "Click" onSettingsBrowseRar
        dotNet.addEventHandler groundLink "Click" onOpen3DGround
        dotNet.addEventHandler maxPkgLink "Click" onOpenMaxPkg
        dotNet.addEventHandler donateButton "Click" onDonate
        dotNet.addEventHandler settingsForm "FormClosed" onSettingsFormClosed

        enableAccelerators = false
        settingsForm.Show mainForm
        return true
    ),

    fn onSettingsButtonClick senderObject eventArgs = (
        return showSettingsForm()
    ),

    fn compareFilePaths firstFilePath secondFilePath = (
        local firstLowerPath = toLower (firstFilePath as string)
        local secondLowerPath = toLower (secondFilePath as string)
        if (firstLowerPath < secondLowerPath) do return -1
        if (firstLowerPath > secondLowerPath) do return 1
        return 0
    ),

    fn isArchiveExtension fileExtension = (
        return ((findItem #(".zip", ".rar", ".7z") fileExtension) > 0)
    ),

    fn isModelExtension fileExtension = (
        return ((findItem #(".max", ".fbx", ".obj", ".3ds", ".iges", ".igs", ".skp", ".dwg", ".dae", ".stl", ".abc", ".dxf") fileExtension) > 0)
    ),

    fn isReadableBitmap filePath = (
        local bitmapInfoData = undefined
        try (bitmapInfoData = getBitmapInfo filePath) catch (bitmapInfoData = undefined)
        return (bitmapInfoData != undefined)
    ),

    fn findFilesByExtensions rootFolderPath extensionArray = (
        local foundFilePaths = #()
        local searchOption = (dotNetClass "System.IO.SearchOption").AllDirectories
        for fileExtension in extensionArray do (
            join foundFilePaths ((dotNetClass "System.IO.Directory").GetFiles rootFolderPath ("*" + fileExtension) searchOption)
        )
        qsort foundFilePaths compareFilePaths
        return foundFilePaths
    ),

    fn makeRelativeFilePath rootFolderPath sourceFilePath = (
        local normalizedRoot = normalizeFolderPath ((dotNetClass "System.IO.Path").GetFullPath rootFolderPath)
        local normalizedSource = (dotNetClass "System.IO.Path").GetFullPath sourceFilePath
        if (findString (toLower normalizedSource) (toLower normalizedRoot) == 1) do return (substring normalizedSource (normalizedRoot.count + 1) -1)
        return normalizedSource
    ),

    fn getRendererTagFromFile filePath = (
        local baseFileName = toLower ((dotNetClass "System.IO.Path").GetFileNameWithoutExtension filePath)
        local normalizedFileName = substituteString (substituteString baseFileName "-" "_") "." "_"
        local fileTokens = filterString normalizedFileName "_ "
        if (findString baseFileName "corona" != undefined or findString baseFileName "coron" != undefined or (findItem fileTokens "crn") > 0) do return "corona"
        if (findString baseFileName "vray" != undefined or findString baseFileName "v-ray" != undefined or findString baseFileName "v_ray" != undefined or (findItem fileTokens "vr") > 0) do return "vray"
        return "other"
    ),

    fn getCurrentRendererTag = (
        local rendererClassName = toLower ((classOf renderers.current) as string)
        if (findString rendererClassName "corona" != undefined) do return "corona"
        if (findString rendererClassName "vray" != undefined or findString rendererClassName "v_ray" != undefined) do return "vray"
        return "other"
    ),

    fn get3dsMaxYearFromFormatVersion formatVersion = (
        local versionYear = 2000 + (((formatVersion as integer) / 1000) - 2)
        return versionYear as integer
    ),

    fn inspectMaxCandidate maxFilePath rootFolderPath = (
        local candidateData = DropperSceneCandidateData sourceFilePath:maxFilePath relativeFilePath:(makeRelativeFilePath rootFolderPath maxFilePath) fileExtension:".max" rendererTag:(getRendererTagFromFile maxFilePath)
        if (not isMaxFile maxFilePath) do (
            candidateData.isCompatible = false
            candidateData.errorMessage = "Invalid MAX file"
            return candidateData
        )
        local versionData = undefined
        try (versionData = getMaxFileVersionData maxFilePath) catch (versionData = undefined)
        if (versionData != undefined and versionData.count > 0) do (
            candidateData.versionLabel = "3ds Max " + ((get3dsMaxYearFromFormatVersion versionData[1]) as string)
            if (versionData[1] > (maxVersion())[1]) do (
                candidateData.isCompatible = false
                candidateData.errorMessage = "Saved by a newer MAX file format"
                return candidateData
            )
        )
        local missingDllNames = #()
        local objectNames = undefined
        try (objectNames = getMAXFileObjectNames maxFilePath quiet:true missingDLLsList:&missingDllNames) catch (
            try (objectNames = getMAXFileObjectNames maxFilePath quiet:true) catch (objectNames = undefined)
        )
        if (objectNames == undefined) do candidateData.warningMessage = "Scene preview was unavailable"
        if (missingDllNames != undefined and missingDllNames.count > 0) do candidateData.warningMessage = (missingDllNames.count as string) + " missing plug-in DLL(s)"
        return candidateData
    ),

    fn chooseSceneCandidate candidateArray dialogTitle = (
        if (candidateArray.count == 0) do return undefined
        if (candidateArray.count == 1) do return candidateArray[1]
        local chooserForm = dotNetObject "System.Windows.Forms.Form"
        chooserForm.Text = dialogTitle
        chooserForm.FormBorderStyle = (dotNetClass "System.Windows.Forms.FormBorderStyle").FixedToolWindow
        chooserForm.ClientSize = dotNetObject "System.Drawing.Size" 620 320
        chooserForm.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").CenterParent
        chooserForm.ShowInTaskbar = false
        local candidateListBox = dotNetObject "System.Windows.Forms.ListBox"
        candidateListBox.Location = dotNetObject "System.Drawing.Point" 10 10
        candidateListBox.Size = dotNetObject "System.Drawing.Size" 600 260
        candidateListBox.HorizontalScrollbar = true
        for candidateData in candidateArray do (
            local displayContent = candidateData.relativeFilePath + " | " + candidateData.rendererTag
            if (candidateData.versionLabel != "") do displayContent += " | " + candidateData.versionLabel
            if (candidateData.warningMessage != "") do displayContent += " | WARNING: " + candidateData.warningMessage
            candidateListBox.Items.Add displayContent
        )
        candidateListBox.SelectedIndex = 0
        chooserForm.Controls.Add candidateListBox
        local useButton = dotNetObject "System.Windows.Forms.Button"
        useButton.Text = "Use Selected"
        useButton.Location = dotNetObject "System.Drawing.Point" 390 280
        useButton.Size = dotNetObject "System.Drawing.Size" 130 28
        useButton.DialogResult = (dotNetClass "System.Windows.Forms.DialogResult").OK
        chooserForm.Controls.Add useButton
        local cancelButton = dotNetObject "System.Windows.Forms.Button"
        cancelButton.Text = "Cancel"
        cancelButton.Location = dotNetObject "System.Drawing.Point" 530 280
        cancelButton.Size = dotNetObject "System.Drawing.Size" 80 28
        cancelButton.DialogResult = (dotNetClass "System.Windows.Forms.DialogResult").Cancel
        chooserForm.Controls.Add cancelButton
        chooserForm.AcceptButton = useButton
        chooserForm.CancelButton = cancelButton
        local dialogResult = chooserForm.ShowDialog mainForm
        local selectedIndex = candidateListBox.SelectedIndex
        chooserForm.Dispose()
        if (dialogResult != (dotNetClass "System.Windows.Forms.DialogResult").OK or selectedIndex < 0) do return undefined
        return candidateArray[selectedIndex + 1]
    ),

    fn selectMaxCandidate rootFolderPath = (
        local maxFilePaths = findFilesByExtensions rootFolderPath #(".max")
        local compatibleCandidates = #()
        for maxFilePath in maxFilePaths do (
            local candidateData = inspectMaxCandidate maxFilePath rootFolderPath
            if (candidateData.isCompatible) then (
                append compatibleCandidates candidateData
                if (candidateData.warningMessage != "") do addLog (candidateData.relativeFilePath + ": " + candidateData.warningMessage) severityLevel:2
            ) else (
                addLog (candidateData.relativeFilePath + ": " + candidateData.errorMessage) severityLevel:2
            )
        )
        if (compatibleCandidates.count == 0) do return undefined
        if (compatibleCandidates.count == 1) do return compatibleCandidates[1]
        local rendererTag = getCurrentRendererTag()
        local rendererMatches = for candidateData in compatibleCandidates where candidateData.rendererTag == rendererTag collect candidateData
        if (rendererMatches.count == 1) do return rendererMatches[1]
        if (rendererMatches.count > 1) do return chooseSceneCandidate rendererMatches "Choose MAX file"
        return chooseSceneCandidate compatibleCandidates "Choose MAX file"
    ),

    fn selectFallbackCandidate rootFolderPath = (
        local extensionGroups = #(#(".fbx"), #(".obj"), #(".3ds"), #(".iges", ".igs"), #(".skp"), #(".dwg"), #(".dae"), #(".stl"), #(".abc"), #(".dxf"))
        for extensionGroup in extensionGroups do (
            local candidateFilePaths = findFilesByExtensions rootFolderPath extensionGroup
            if (candidateFilePaths.count > 0) do (
                local candidateArray = for candidateFilePath in candidateFilePaths collect (
                    DropperSceneCandidateData sourceFilePath:candidateFilePath relativeFilePath:(makeRelativeFilePath rootFolderPath candidateFilePath) fileExtension:(toLower ((dotNetClass "System.IO.Path").GetExtension candidateFilePath))
                )
                return chooseSceneCandidate candidateArray "Choose model file"
            )
        )
        return undefined
    ),

    fn collectSceneNodeHandles = (
        local nodeHandles = #()
        for sceneNode in objects do append nodeHandles sceneNode.handle
        return nodeHandles
    ),

    fn collectNewSceneNodes handlesBefore = (
        local newSceneNodes = #()
        for sceneNode in objects where (findItem handlesBefore sceneNode.handle) == 0 do append newSceneNodes sceneNode
        return newSceneNodes
    ),

    fn performSafeMerge maxFilePath = (
        local isSuccessful = false
        try (
            if (settingsData.renameDuplicateNodes and settingsData.renameDuplicateMaterials) then (
                isSuccessful = mergeMAXFile maxFilePath #select #noRedraw #autoRenameDups #renameMtlDups #neverReparent quiet:true
            ) else if (settingsData.renameDuplicateNodes and not settingsData.renameDuplicateMaterials) then (
                isSuccessful = mergeMAXFile maxFilePath #select #noRedraw #autoRenameDups #useSceneMtlDups #neverReparent quiet:true
            ) else if (not settingsData.renameDuplicateNodes and settingsData.renameDuplicateMaterials) then (
                isSuccessful = mergeMAXFile maxFilePath #select #noRedraw #skipDups #renameMtlDups #neverReparent quiet:true
            ) else (
                isSuccessful = mergeMAXFile maxFilePath #select #noRedraw #skipDups #useSceneMtlDups #neverReparent quiet:true
            )
        ) catch (
            addLog ("MAX merge failed: " + (getCurrentException() as string)) severityLevel:3
            isSuccessful = false
        )
        return isSuccessful
    ),

    fn performModelImport modelFilePath = (
        local isSuccessful = false
        try (
            if (settingsData.showImporterDialogs) then (isSuccessful = importFile modelFilePath) else (isSuccessful = importFile modelFilePath #noPrompt)
        ) catch (
            addLog ("Model import failed: " + (getCurrentException() as string)) severityLevel:3
            isSuccessful = false
        )
        return isSuccessful
    ),

    fn getRootNodes sceneNodeArray = (
        local rootNodes = #()
        for sceneNode in sceneNodeArray do (
            if (sceneNode.parent == undefined or (findItem sceneNodeArray sceneNode.parent) == 0) do append rootNodes sceneNode
        )
        return rootNodes
    ),

    fn groundNewNodes sceneNodeArray = (
        if (sceneNodeArray.count == 0) do return false
        local geometryNodes = for sceneNode in sceneNodeArray where (superClassOf sceneNode == GeometryClass) collect sceneNode
        local boundingNodes = if geometryNodes.count > 0 then geometryNodes else sceneNodeArray
        local minimumZ = 1e30
        local hasBounds = false
        for sceneNode in boundingNodes do (
            try (
                local nodeBounds = nodeGetBoundingBox sceneNode (matrix3 1)
                minimumZ = amin minimumZ nodeBounds[1].z nodeBounds[2].z
                hasBounds = true
            ) catch()
        )
        if (not hasBounds) do return false
        local zOffset = -minimumZ
        for rootNode in (getRootNodes sceneNodeArray) do try (rootNode.pos.z += zOffset) catch()
        return true
    ),

    fn makeUniqueLayerName sourceFilePath = (
        local baseLayerName = "DROP_" + (dotNetClass "System.IO.Path").GetFileNameWithoutExtension sourceFilePath
        baseLayerName = substituteString (substituteString baseLayerName ":" "_") "/" "_"
        local candidateLayerName = baseLayerName
        local suffixNumber = 2
        while (LayerManager.getLayerFromName candidateLayerName != undefined) do (
            candidateLayerName = baseLayerName + "_" + formattedPrint suffixNumber format:"03d"
            suffixNumber += 1
        )
        return candidateLayerName
    ),

    fn assignNodesToUniqueLayer sceneNodeArray sourceFilePath = (
        if (not settingsData.createUniqueLayer or sceneNodeArray.count == 0) do return false
        local destinationLayer = LayerManager.newLayerFromName (makeUniqueLayerName sourceFilePath)
        if (destinationLayer == undefined) do return false
        for sceneNode in sceneNodeArray do try (destinationLayer.addNode sceneNode) catch()
        return true
    ),

    fn getMapClassArray = (
        local mapClasses = #(Bitmaptexture)
        local optionalClass = undefined
        try (optionalClass = CoronaBitmap) catch (optionalClass = undefined)
        if (optionalClass != undefined) do appendIfUnique mapClasses optionalClass
        try (optionalClass = VRayBitmap) catch (optionalClass = undefined)
        if (optionalClass != undefined) do appendIfUnique mapClasses optionalClass
        try (optionalClass = VRayHDRI) catch (optionalClass = undefined)
        if (optionalClass != undefined) do appendIfUnique mapClasses optionalClass
        return mapClasses
    ),

    fn getTextureMapsForNodes sceneNodeArray = (
        local textureMaps = #()
        for sceneNode in sceneNodeArray do (
            for mapClass in (getMapClassArray()) do (
                local nodeMaps = #()
                try (nodeMaps = getClassInstances mapClass target:sceneNode processChildren:true) catch (nodeMaps = #())
                for textureMap in nodeMaps do appendIfUnique textureMaps textureMap
            )
        )
        return textureMaps
    ),

    fn countCommonTrailingSegments firstFilePath secondFilePath = (
        local firstSegments = filterString (toLower (substituteString firstFilePath "/" "\\")) "\\"
        local secondSegments = filterString (toLower (substituteString secondFilePath "/" "\\")) "\\"
        local firstIndex = firstSegments.count
        local secondIndex = secondSegments.count
        local matchingCount = 0
        while (firstIndex > 0 and secondIndex > 0 and firstSegments[firstIndex] == secondSegments[secondIndex]) do (
            matchingCount += 1
            firstIndex -= 1
            secondIndex -= 1
        )
        return matchingCount
    ),

    fn resolveTextureFile originalFilePath indexedFilePaths = (
        local originalFileName = toLower ((dotNetClass "System.IO.Path").GetFileName originalFilePath)
        local fileMatches = for indexedFilePath in indexedFilePaths where (toLower ((dotNetClass "System.IO.Path").GetFileName indexedFilePath)) == originalFileName collect indexedFilePath
        if (fileMatches.count == 0) do return #(#missing, "", #())
        if (fileMatches.count == 1) do return #(#found, fileMatches[1], fileMatches)
        local bestScore = -1
        local bestMatches = #()
        for matchedFilePath in fileMatches do (
            local matchScore = countCommonTrailingSegments originalFilePath matchedFilePath
            if (matchScore > bestScore) then (
                bestScore = matchScore
                bestMatches = #(matchedFilePath)
            ) else if (matchScore == bestScore) do append bestMatches matchedFilePath
        )
        if (bestMatches.count == 1) do return #(#found, bestMatches[1], fileMatches)
        return #(#ambiguous, "", bestMatches)
    ),

    fn textureMapIsSharedWithOldNode textureMap sceneNodeArray = (
        local dependentNodes = #()
        try (dependentNodes = refs.dependentNodes textureMap) catch (dependentNodes = #())
        for dependentNode in dependentNodes where (findItem sceneNodeArray dependentNode) == 0 do return true
        return false
    ),

    fn getTextureMapFilePath textureMap = (
        if (textureMap == undefined) do return ""
        local filePropertyNames = #(#filename, #file, #HDRIMapName)
        for filePropertyName in filePropertyNames do (
            if (isProperty textureMap filePropertyName) do (
                local filePathContent = ""
                try (filePathContent = getProperty textureMap filePropertyName) catch (filePathContent = "")
                if (filePathContent != undefined and filePathContent != "") do return (filePathContent as string)
            )
        )
        return ""
    ),

    fn setTextureMapFilePath textureMap filePathContent = (
        if (textureMap == undefined or filePathContent == undefined or filePathContent == "") do return false
        local filePropertyNames = #(#filename, #file, #HDRIMapName)
        for filePropertyName in filePropertyNames do (
            if (isProperty textureMap filePropertyName) do (
                try (
                    setProperty textureMap filePropertyName filePathContent
                    return true
                ) catch()
            )
        )
        return false
    ),

    fn relinkTextures sceneNodeArray searchFolderPath = (
        local relinkData = DropperRelinkResultData()
        if (sceneNodeArray.count == 0 or searchFolderPath == "" or not (dotNetClass "System.IO.Directory").Exists searchFolderPath) do return relinkData
        local indexedFilePaths = (dotNetClass "System.IO.Directory").GetFiles searchFolderPath "*" ((dotNetClass "System.IO.SearchOption").AllDirectories)
        local textureMaps = getTextureMapsForNodes sceneNodeArray
        for textureMap in textureMaps do (
            local originalFilePath = ""
            try (originalFilePath = getTextureMapFilePath textureMap) catch (originalFilePath = "")
            if (originalFilePath != undefined and originalFilePath != "") do (
                if ((dotNetClass "System.IO.File").Exists originalFilePath) then (
                    relinkData.availableCount += 1
                ) else if (textureMapIsSharedWithOldNode textureMap sceneNodeArray) then (
                    relinkData.sharedCount += 1
                    addLog ("Skipped a texture shared with the existing scene: " + originalFilePath) severityLevel:2
                ) else (
                    local resolutionData = resolveTextureFile originalFilePath indexedFilePaths
                    if (resolutionData[1] == #found) then (
                        local isRelinked = false
                        try (isRelinked = setTextureMapFilePath textureMap resolutionData[2]) catch (isRelinked = false)
                        if (isRelinked) then (
                            relinkData.relinkedCount += 1
                            addLog ("Relinked texture: " + originalFilePath + " -> " + resolutionData[2]) severityLevel:1
                        ) else (
                            relinkData.missingCount += 1
                            addLog ("Could not assign texture: " + originalFilePath) severityLevel:3
                        )
                    ) else if (resolutionData[1] == #ambiguous) then (
                        relinkData.ambiguousCount += 1
                        addLog ("Ambiguous texture: " + originalFilePath + " | candidates: " + (resolutionData[3] as string)) severityLevel:2
                    ) else (
                        relinkData.missingCount += 1
                        addLog ("Missing texture: " + originalFilePath) severityLevel:2
                    )
                )
            )
        )
        addLog ("Textures - available: " + (relinkData.availableCount as string) + ", relinked: " + (relinkData.relinkedCount as string) + ", ambiguous: " + (relinkData.ambiguousCount as string) + ", missing: " + (relinkData.missingCount as string) + ", shared: " + (relinkData.sharedCount as string))
        return relinkData
    ),

    fn postProcessImportedNodes sceneNodeArray sourceFilePath searchFolderPath = (
        if (sceneNodeArray.count == 0) do return false
        if (not groundNewNodes sceneNodeArray) do addLog "Could not calculate model bounds; Z position was preserved." severityLevel:2
        assignNodesToUniqueLayer sceneNodeArray sourceFilePath
        relinkTextures sceneNodeArray searchFolderPath
        try (select sceneNodeArray; max tool zoomextents) catch (addLog "Viewport zoom could not be completed." severityLevel:2)
        redrawViews()
        return true
    ),

    fn processModelCandidate candidateData searchFolderPath layerSourceFilePath:undefined = (
        if (candidateData == undefined) do return false
        local effectiveLayerSourceFilePath = if layerSourceFilePath == undefined then candidateData.sourceFilePath else layerSourceFilePath
        local handlesBefore = collectSceneNodeHandles()
        local isSuccessful = false
        if (candidateData.fileExtension == ".max") then (
            local currentRendererTag = getCurrentRendererTag()
            if (candidateData.rendererTag != "other" and currentRendererTag != "other" and candidateData.rendererTag != currentRendererTag) do addLog ("Renderer mismatch accepted: scene is " + currentRendererTag + ", file is " + candidateData.rendererTag + ".")
            isSuccessful = performSafeMerge candidateData.sourceFilePath
        ) else (
            isSuccessful = performModelImport candidateData.sourceFilePath
        )
        local newSceneNodes = collectNewSceneNodes handlesBefore
        if (not isSuccessful or newSceneNodes.count == 0) do (
            if (newSceneNodes.count > 0) do try (delete newSceneNodes) catch()
            return false
        )
        postProcessImportedNodes newSceneNodes effectiveLayerSourceFilePath searchFolderPath
        addLog ("Imported " + (newSceneNodes.count as string) + " node(s) from: " + candidateData.sourceFilePath) severityLevel:1
        return true
    ),

    fn createMaterialForRenderer = (
        local rendererTag = getCurrentRendererTag()
        local materialInstance = undefined
        local materialClass = undefined
        if (rendererTag == "corona") do (
            try (materialClass = CoronaPhysicalMtl) catch (materialClass = undefined)
            if (materialClass == undefined) do try (materialClass = CoronaLegacyMtl) catch (materialClass = undefined)
            if (materialClass == undefined) do try (materialClass = CoronaMtl) catch (materialClass = undefined)
        )
        if (rendererTag == "vray") do try (materialClass = VRayMtl) catch (materialClass = undefined)
        try (
            if (materialClass != undefined) do materialInstance = createInstance materialClass
        ) catch (materialInstance = undefined)
        if (materialInstance == undefined) do materialInstance = standardMaterial()
        return materialInstance
    ),

    fn assignBitmapToMaterial materialInstance bitmapMap = (
        local mapProperties = #(#baseTexmap, #texmapDiffuse, #texmap_diffuse, #diffuseMap)
        for mapProperty in mapProperties do (
            if (isProperty materialInstance mapProperty) do (
                try (
                    setProperty materialInstance mapProperty bitmapMap
                    try (showTextureMap materialInstance bitmapMap true) catch()
                    try (if (isProperty materialInstance #showInViewport) do setProperty materialInstance #showInViewport true) catch()
                    try (if (isProperty materialInstance #twoSided) do setProperty materialInstance #twoSided true) catch()
                    return true
                ) catch()
            )
        )
        return false
    ),

    fn createImagePlanes imageFilePaths = (
        local imageDataArray = #()
        local totalWidth = 0.0
        local spacingSize = (units.decodeValue "1m") * 0.1
        for imageFilePath in imageFilePaths do (
            local openedBitmap = undefined
            try (openedBitmap = openBitmap imageFilePath) catch (openedBitmap = undefined)
            if (openedBitmap != undefined) then (
                local pixelWidth = openedBitmap.width as float
                local pixelHeight = openedBitmap.height as float
                close openedBitmap
                local longSide = units.decodeValue "1m"
                local planeWidth = longSide
                local planeHeight = longSide
                if (pixelWidth >= pixelHeight) then (
                    planeHeight = longSide * pixelHeight / pixelWidth
                ) else (
                    planeWidth = longSide * pixelWidth / pixelHeight
                )
                append imageDataArray #(imageFilePath, planeWidth, planeHeight)
                totalWidth += planeWidth
            ) else (
                addLog ("Could not open bitmap: " + imageFilePath) severityLevel:3
            )
        )
        if (imageDataArray.count == 0) do return false
        totalWidth += spacingSize * (imageDataArray.count - 1)
        local currentX = -totalWidth * 0.5
        local createdPlanes = #()
        for imageData in imageDataArray do (
            local imageFilePath = imageData[1]
            local planeWidth = imageData[2]
            local planeHeight = imageData[3]
            local planeNode = plane width:planeWidth length:planeHeight widthsegs:1 lengthsegs:1 mapcoords:true
            planeNode.rotation = eulerAngles 90 0 0
            planeNode.pos = [currentX + planeWidth * 0.5, 0, planeHeight * 0.5]
            planeNode.name = uniqueName ("DROP_" + (dotNetClass "System.IO.Path").GetFileNameWithoutExtension imageFilePath + "_")
            local bitmapMap = bitmapTexture filename:imageFilePath
            local materialInstance = createMaterialForRenderer()
            materialInstance.name = uniqueName ("DROP_MTL_" + (dotNetClass "System.IO.Path").GetFileNameWithoutExtension imageFilePath + "_")
            if (assignBitmapToMaterial materialInstance bitmapMap) then (
                planeNode.material = materialInstance
            ) else (
                addLog ("No supported bitmap slot was found on material: " + materialInstance.name) severityLevel:3
            )
            append createdPlanes planeNode
            currentX += planeWidth + spacingSize
        )
        if (settingsData.createUniqueLayer) do assignNodesToUniqueLayer createdPlanes imageFilePaths[1]
        try (select createdPlanes; max tool zoomextents) catch (addLog "Viewport zoom could not be completed." severityLevel:2)
        redrawViews()
        addLog ("Created " + (createdPlanes.count as string) + " image plane(s).") severityLevel:1
        return true
    ),

    fn getOrCreateExtractionFolder baseFolderPath desiredFolderName = (
        local normalizedBaseFolder = normalizeFolderPath baseFolderPath
        if (not (dotNetClass "System.IO.Directory").Exists normalizedBaseFolder) do (
            (dotNetClass "System.IO.Directory").CreateDirectory normalizedBaseFolder
        )
        local extractionFolderPath = normalizedBaseFolder + desiredFolderName
        if (not (dotNetClass "System.IO.Directory").Exists extractionFolderPath) do (
            (dotNetClass "System.IO.Directory").CreateDirectory extractionFolderPath
        )
        return normalizeFolderPath extractionFolderPath
    ),

    fn getExtractionRoot archiveFilePath = (
        local baseFolderPath = ""
        if (settingsData.extractNextToArchive) then (
            baseFolderPath = (dotNetClass "System.IO.Path").GetDirectoryName archiveFilePath
        ) else (
            baseFolderPath = settingsData.customExtractFolder
            if (baseFolderPath == "") do throw "The custom extraction folder is empty."
        )
        local archiveFolderName = (dotNetClass "System.IO.Path").GetFileNameWithoutExtension archiveFilePath
        return getOrCreateExtractionFolder baseFolderPath archiveFolderName
    ),

    fn getRegistryApplicationPath executableFileName = (
        local registryClass = dotNetClass "Microsoft.Win32.Registry"
        local registryKeyPaths = #(
            "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\" + executableFileName,
            "HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\App Paths\\" + executableFileName
        )
        for registryKeyPath in registryKeyPaths do (
            local executablePath = undefined
            try (executablePath = registryClass.GetValue registryKeyPath "" undefined) catch (executablePath = undefined)
            if (executablePath != undefined and (dotNetClass "System.IO.File").Exists (executablePath as string)) do return (executablePath as string)
        )
        return ""
    ),

    fn classifyRarExecutable executablePath = (
        local executableName = toLower ((dotNetClass "System.IO.Path").GetFileNameWithoutExtension executablePath)
        if (findString executableName "rar" != undefined) do return #winrar
        return #sevenzip
    ),

    fn addExistingExecutable candidateExecutables executablePath = (
        if (executablePath != undefined and executablePath != "" and (dotNetClass "System.IO.File").Exists executablePath) do (
            appendIfUnique candidateExecutables executablePath
        )
        return candidateExecutables
    ),

    fn findRarProvider = (
        local candidateExecutables = #()
        addExistingExecutable candidateExecutables settingsData.customRarExecutable
        addExistingExecutable candidateExecutables (getRegistryApplicationPath "WinRAR.exe")
        addExistingExecutable candidateExecutables (getRegistryApplicationPath "UnRAR.exe")
        local environmentClass = dotNetClass "System.Environment"
        local specialFolderClass = dotNetClass "System.Environment+SpecialFolder"
        local programFilesFolder = environmentClass.GetFolderPath specialFolderClass.ProgramFiles
        local programFilesX86Folder = environmentClass.GetFolderPath specialFolderClass.ProgramFilesX86
        addExistingExecutable candidateExecutables (programFilesFolder + "\\WinRAR\\WinRAR.exe")
        addExistingExecutable candidateExecutables (programFilesFolder + "\\WinRAR\\UnRAR.exe")
        addExistingExecutable candidateExecutables (programFilesFolder + "\\7-Zip\\7z.exe")
        addExistingExecutable candidateExecutables (programFilesX86Folder + "\\WinRAR\\WinRAR.exe")
        addExistingExecutable candidateExecutables (programFilesX86Folder + "\\7-Zip\\7z.exe")
        for executablePath in candidateExecutables do (
            local providerType = classifyRarExecutable executablePath
            if (providerType == #sevenzip) then (
                local libraryFilePath = (dotNetClass "System.IO.Path").Combine ((dotNetClass "System.IO.Path").GetDirectoryName executablePath) "7z.dll"
                if ((dotNetClass "System.IO.File").Exists libraryFilePath) do return (DropperArchiveProviderData providerType:#sevenzip executablePath:executablePath displayName:"7-Zip")
            ) else (
                return (DropperArchiveProviderData providerType:#winrar executablePath:executablePath displayName:"WinRAR")
            )
        )
        return undefined
    ),

    fn getArchiveProvider archiveFilePath = (
        local fileExtension = toLower ((dotNetClass "System.IO.Path").GetExtension archiveFilePath)
        if (fileExtension == ".zip") do return (DropperArchiveProviderData providerType:#dotnetzip executablePath:"" displayName:"Windows ZIP")
        if (fileExtension == ".7z") do (
            local bundledExecutablePath = scriptFolderPath + "bin\\7za.exe"
            if ((dotNetClass "System.IO.File").Exists bundledExecutablePath) do return (DropperArchiveProviderData providerType:#sevenzip executablePath:bundledExecutablePath displayName:"Bundled 7-Zip")
            return undefined
        )
        if (fileExtension == ".rar") do return findRarProvider()
        return undefined
    ),

    fn cleanupStagingFolder stagingFolderPath = (
        if (stagingFolderPath == undefined or stagingFolderPath == "") do return false
        local fullStagingPath = (dotNetClass "System.IO.Path").GetFullPath stagingFolderPath
        local expectedPrefix = toLower ((dotNetClass "System.IO.Path").Combine ((dotNetClass "System.IO.Path").GetTempPath()) "DropperStaging_")
        if (findString (toLower fullStagingPath) expectedPrefix != 1) do return false
        try (
            if ((dotNetClass "System.IO.Directory").Exists fullStagingPath) do (dotNetClass "System.IO.Directory").Delete fullStagingPath true
        ) catch()
        return true
    ),

    fn runResponsiveProcess executablePath argumentContent displayName = (
        local processInfo = dotNetObject "System.Diagnostics.ProcessStartInfo"
        processInfo.FileName = executablePath
        processInfo.Arguments = argumentContent
        processInfo.UseShellExecute = false
        processInfo.CreateNoWindow = true
        local processObject = undefined
        try (processObject = (dotNetClass "System.Diagnostics.Process").Start processInfo) catch (
            addLog ("Could not start " + displayName + ": " + (getCurrentException() as string)) severityLevel:3
            return -1
        )
        while (not processObject.HasExited and not isCancelRequested) do (
            (dotNetClass "System.Windows.Forms.Application").DoEvents()
            (dotNetClass "System.Threading.Thread").Sleep 30
        )
        if (isCancelRequested and not processObject.HasExited) do try (processObject.Kill()) catch()
        local exitCodeNumber = -1
        try (exitCodeNumber = processObject.ExitCode) catch()
        try (processObject.Dispose()) catch()
        return exitCodeNumber
    ),

    fn copyStagedOutput stagedOutputPath targetFolderPath = (
        local searchOption = (dotNetClass "System.IO.SearchOption").AllDirectories
        local stagedRoot = normalizeFolderPath ((dotNetClass "System.IO.Path").GetFullPath stagedOutputPath)
        local targetRoot = normalizeFolderPath ((dotNetClass "System.IO.Path").GetFullPath targetFolderPath)
        local stagedFiles = (dotNetClass "System.IO.Directory").GetFiles stagedRoot "*" searchOption
        for stagedFilePath in stagedFiles do (
            local relativeFilePath = substring stagedFilePath (stagedRoot.count + 1) -1
            local destinationFilePath = (dotNetClass "System.IO.Path").Combine targetRoot relativeFilePath
            local destinationFolderPath = (dotNetClass "System.IO.Path").GetDirectoryName destinationFilePath
            if (not (dotNetClass "System.IO.Directory").Exists destinationFolderPath) do (dotNetClass "System.IO.Directory").CreateDirectory destinationFolderPath
            (dotNetClass "System.IO.File").Copy stagedFilePath destinationFilePath true
        )
        return true
    ),

    fn extractWithExternalProvider archiveTask providerData = (
        local stagingFolderPath = (dotNetClass "System.IO.Path").Combine ((dotNetClass "System.IO.Path").GetTempPath()) ("DropperStaging_" + createGuidString())
        local stagedOutputPath = (dotNetClass "System.IO.Path").Combine stagingFolderPath "out"
        (dotNetClass "System.IO.Directory").CreateDirectory stagedOutputPath
        local stagedArchivePath = (dotNetClass "System.IO.Path").Combine stagingFolderPath ("input" + (dotNetClass "System.IO.Path").GetExtension archiveTask.sourceFilePath)
        try ((dotNetClass "System.IO.File").Copy archiveTask.sourceFilePath stagedArchivePath false) catch (
            addLog ("Could not create an ASCII archive copy: " + (getCurrentException() as string)) severityLevel:3
            cleanupStagingFolder stagingFolderPath
            return false
        )
        local probeArguments = ""
        local extractArguments = ""
        if (providerData.providerType == #sevenzip) then (
            probeArguments = "t -bd -y \"" + stagedArchivePath + "\""
            extractArguments = "x -bd -y \"" + stagedArchivePath + "\" -o\"" + stagedOutputPath + "\""
        ) else (
            probeArguments = "t -inul \"" + stagedArchivePath + "\""
            extractArguments = "x -y -inul \"" + stagedArchivePath + "\" \"" + normalizeFolderPath stagedOutputPath + "\""
        )
        setStatus ("Checking " + providerData.displayName)
        if ((runResponsiveProcess providerData.executablePath probeArguments providerData.displayName) != 0) do (
            addLog (providerData.displayName + " cannot read: " + archiveTask.sourceFilePath) severityLevel:3
            cleanupStagingFolder stagingFolderPath
            return false
        )
        setStatus ("Extracting " + (dotNetClass "System.IO.Path").GetFileName archiveTask.sourceFilePath)
        if ((runResponsiveProcess providerData.executablePath extractArguments providerData.displayName) != 0) do (
            addLog (providerData.displayName + " could not extract: " + archiveTask.sourceFilePath) severityLevel:3
            cleanupStagingFolder stagingFolderPath
            return false
        )
        local isSuccessful = false
        try (
            copyStagedOutput stagedOutputPath archiveTask.targetFolderPath
            isSuccessful = true
        ) catch (
            addLog ("Could not move extracted files: " + (getCurrentException() as string)) severityLevel:3
            isSuccessful = false
        )
        cleanupStagingFolder stagingFolderPath
        return isSuccessful
    ),

    fn extractZipArchive archiveTask = (
        local isSuccessful = false
        local zipFileStream = undefined
        local zipArchiveObject = undefined
        try (
            dotNet.loadAssembly "System.IO.Compression"
            dotNet.loadAssembly "System.IO.Compression.FileSystem"
            zipFileStream = (dotNetClass "System.IO.File").OpenRead archiveTask.sourceFilePath
            zipArchiveObject = dotNetObject "System.IO.Compression.ZipArchive" zipFileStream ((dotNetClass "System.IO.Compression.ZipArchiveMode").Read) false
            local targetRoot = normalizeFolderPath ((dotNetClass "System.IO.Path").GetFullPath archiveTask.targetFolderPath)
            for entryIndex in 0 to (zipArchiveObject.Entries.Count - 1) while (not isCancelRequested) do (
                local archiveEntry = zipArchiveObject.Entries.Item[entryIndex]
                local destinationPath = (dotNetClass "System.IO.Path").GetFullPath ((dotNetClass "System.IO.Path").Combine targetRoot archiveEntry.FullName)
                if (findString (toLower destinationPath) (toLower targetRoot) != 1) do throw "ZIP entry attempted to leave the extraction folder."
                if (archiveEntry.Name == "") then (
                    (dotNetClass "System.IO.Directory").CreateDirectory destinationPath
                ) else (
                    local destinationFolderPath = (dotNetClass "System.IO.Path").GetDirectoryName destinationPath
                    if (not (dotNetClass "System.IO.Directory").Exists destinationFolderPath) do (dotNetClass "System.IO.Directory").CreateDirectory destinationFolderPath
                    local inputStream = archiveEntry.Open()
                    local outputStream = (dotNetClass "System.IO.File").Create destinationPath
                    inputStream.CopyTo outputStream
                    outputStream.Dispose()
                    inputStream.Dispose()
                )
                if (mod entryIndex 8 == 0) do (dotNetClass "System.Windows.Forms.Application").DoEvents()
            )
            isSuccessful = not isCancelRequested
        ) catch (
            addLog ("ZIP extraction failed: " + (getCurrentException() as string)) severityLevel:3
            isSuccessful = false
        )
        try (if (zipArchiveObject != undefined) do zipArchiveObject.Dispose()) catch()
        try (if (zipFileStream != undefined) do zipFileStream.Dispose()) catch()
        return isSuccessful
    ),

    fn extractArchiveTask archiveTask = (
        local providerData = getArchiveProvider archiveTask.sourceFilePath
        if (providerData == undefined) do (
            local fileExtension = toLower ((dotNetClass "System.IO.Path").GetExtension archiveTask.sourceFilePath)
            if (fileExtension == ".rar") then (
                addLog "No RAR-compatible WinRAR or full 7-Zip installation was found." severityLevel:3
            ) else (
                addLog ("Required archive provider is missing: " + archiveTask.sourceFilePath) severityLevel:3
            )
            return false
        )
        if (providerData.providerType == #dotnetzip) then (
            setStatus ("Extracting " + (dotNetClass "System.IO.Path").GetFileName archiveTask.sourceFilePath)
            return extractZipArchive archiveTask
        )
        return extractWithExternalProvider archiveTask providerData
    ),

    fn queueNestedArchives archiveTasks completedTask = (
        if (completedTask.depth >= 5) do return archiveTasks
        local searchOption = (dotNetClass "System.IO.SearchOption").AllDirectories
        local nestedArchivePaths = #()
        for archivePattern in #("*.zip", "*.rar", "*.7z") do join nestedArchivePaths ((dotNetClass "System.IO.Directory").GetFiles completedTask.targetFolderPath archivePattern searchOption)
        for nestedArchivePath in nestedArchivePaths do (
            local nestedFolderName = (dotNetClass "System.IO.Path").GetFileNameWithoutExtension nestedArchivePath + "_extracted"
            local nestedTargetFolder = getOrCreateExtractionFolder ((dotNetClass "System.IO.Path").GetDirectoryName nestedArchivePath) nestedFolderName
            append archiveTasks (DropperArchiveTaskData sourceFilePath:nestedArchivePath targetFolderPath:nestedTargetFolder depth:(completedTask.depth + 1) isTopLevel:false)
        )
        return archiveTasks
    ),

    fn extractArchiveTree archiveFilePath extractionRoot = (
        local archiveTasks = #(DropperArchiveTaskData sourceFilePath:archiveFilePath targetFolderPath:extractionRoot depth:0 isTopLevel:true)
        local taskIndex = 1
        while (taskIndex <= archiveTasks.count and not isCancelRequested) do (
            local archiveTask = archiveTasks[taskIndex]
            taskIndex += 1
            local isSuccessful = extractArchiveTask archiveTask
            if (isSuccessful) then (
                addLog ("Extracted: " + archiveTask.sourceFilePath) severityLevel:1
                archiveTasks = queueNestedArchives archiveTasks archiveTask
            ) else if (archiveTask.isTopLevel) do (
                return false
            )
        )
        return (not isCancelRequested)
    ),

    fn processArchiveContents extractionRoot archiveFilePath = (
        local maxCandidate = selectMaxCandidate extractionRoot
        local isSuccessful = false
        if (maxCandidate != undefined) do isSuccessful = processModelCandidate maxCandidate extractionRoot layerSourceFilePath:archiveFilePath
        if (not isSuccessful) do (
            local fallbackCandidate = selectFallbackCandidate extractionRoot
            if (fallbackCandidate != undefined) then (
                isSuccessful = processModelCandidate fallbackCandidate extractionRoot layerSourceFilePath:archiveFilePath
            ) else (
                addLog ("No supported model was found in: " + extractionRoot) severityLevel:3
            )
        )
        return isSuccessful
    ),

    fn processArchiveFile archiveFilePath = (
        local extractionRoot = ""
        try (
            extractionRoot = getExtractionRoot archiveFilePath
            addLog ("Archive destination: " + extractionRoot)
        ) catch (
            addLog ("Archive setup failed: " + (getCurrentException() as string)) severityLevel:3
            return false
        )
        if (not extractArchiveTree archiveFilePath extractionRoot) do return false
        return processArchiveContents extractionRoot archiveFilePath
    ),

    fn processDirectModel modelFilePath = (
        local fileExtension = toLower ((dotNetClass "System.IO.Path").GetExtension modelFilePath)
        local sourceFolderPath = (dotNetClass "System.IO.Path").GetDirectoryName modelFilePath
        local candidateData = DropperSceneCandidateData sourceFilePath:modelFilePath relativeFilePath:modelFilePath fileExtension:fileExtension rendererTag:(if fileExtension == ".max" then getRendererTagFromFile modelFilePath else "other")
        if (fileExtension == ".max") do (
            candidateData = inspectMaxCandidate modelFilePath sourceFolderPath
            if (not candidateData.isCompatible) do (
                addLog (candidateData.errorMessage + ": " + modelFilePath) severityLevel:3
                return false
            )
            if (candidateData.warningMessage != "") do addLog (candidateData.warningMessage + ": " + modelFilePath) severityLevel:2
        )
        return processModelCandidate candidateData sourceFolderPath
    ),

    fn convertFileCollection fileCollection = (
        local sourceFilePaths = #()
        if (fileCollection == undefined) do return sourceFilePaths
        local collectionLength = 0
        try (collectionLength = fileCollection.Length) catch (collectionLength = 0)
        if (collectionLength > 0) then (
            for collectionIndex in 0 to (collectionLength - 1) do append sourceFilePaths (fileCollection.GetValue collectionIndex as string)
        ) else (
            try (for sourceFilePath in fileCollection do append sourceFilePaths (sourceFilePath as string)) catch()
        )
        return sourceFilePaths
    ),

    fn processDroppedFiles fileCollection = (
        if (isBusy) do (
            addLog "Dropper is already processing files." severityLevel:2
            return false
        )
        local sourceFilePaths = convertFileCollection fileCollection
        if (sourceFilePaths.count == 0) do return false

        isBusy = true
        isCancelRequested = false
        local imageFilePaths = #()
        local successfulCount = 0
        local failedCount = 0

        for sourceFilePath in sourceFilePaths while (not isCancelRequested) do (
            if ((dotNetClass "System.IO.File").Exists sourceFilePath) then (
                local fileExtension = toLower ((dotNetClass "System.IO.Path").GetExtension sourceFilePath)
                local isSuccessful = false
                local isDeferredImage = false
                setStatus ("Processing " + (dotNetClass "System.IO.Path").GetFileName sourceFilePath)
                try (
                    if (isArchiveExtension fileExtension) then (
                        isSuccessful = processArchiveFile sourceFilePath
                    ) else if (isModelExtension fileExtension) then (
                        isSuccessful = processDirectModel sourceFilePath
                    ) else if (isReadableBitmap sourceFilePath) then (
                        append imageFilePaths sourceFilePath
                        isDeferredImage = true
                    ) else (
                        addLog ("Unsupported file: " + sourceFilePath) severityLevel:2
                    )
                ) catch (
                    addLog ("Processing failed: " + sourceFilePath + " | " + (getCurrentException() as string)) severityLevel:3
                    isSuccessful = false
                )
                if (not isDeferredImage) do (
                    if (isSuccessful) then successfulCount += 1 else failedCount += 1
                )
            ) else (
                addLog ("File does not exist: " + sourceFilePath) severityLevel:2
                failedCount += 1
            )
            (dotNetClass "System.Windows.Forms.Application").DoEvents()
        )

        if (imageFilePaths.count > 0 and not isCancelRequested) do (
            setStatus "Creating image planes"
            if (createImagePlanes imageFilePaths) then successfulCount += imageFilePaths.count else failedCount += imageFilePaths.count
        )

        if (isCancelRequested) then (
            addLog "Processing was cancelled." severityLevel:2
            setStatus "Cancelled"
        ) else if (failedCount > 0) then (
            setStatus ("Completed: " + (successfulCount as string) + " successful, " + (failedCount as string) + " failed")
        ) else (
            setStatus ("Completed: " + (successfulCount as string) + " successful")
        )
        isBusy = false
        return (failedCount == 0 and not isCancelRequested)
    ),

    fn onDeferredDropTimerTick senderObject eventArgs = (
        local queuedFilePaths = deferredDropFilePaths
        try (senderObject.Stop()) catch()
        try (senderObject.Dispose()) catch()
        deferredDropTimer = undefined
        deferredDropFilePaths = #()
        if (queuedFilePaths.count > 0) do processDroppedFiles queuedFilePaths
        return true
    ),

    fn queueDroppedFiles fileCollection = (
        if (isBusy or deferredDropTimer != undefined) do (
            addLog "Dropper is already processing files." severityLevel:2
            return false
        )
        local sourceFilePaths = convertFileCollection fileCollection
        if (sourceFilePaths.count == 0) do return false
        deferredDropFilePaths = sourceFilePaths
        deferredDropTimer = dotNetObject "System.Windows.Forms.Timer"
        deferredDropTimer.Interval = 20
        dotNet.addEventHandler deferredDropTimer "Tick" onDeferredDropTimerTick
        deferredDropTimer.Start()
        setStatus ("Queued " + (sourceFilePaths.count as string) + " file(s)")
        return true
    ),

    fn onDropPanelDragDrop senderObject dragEventArgs = (
        local dataFormatsClass = dotNetClass "System.Windows.Forms.DataFormats"
        local droppedFiles = dragEventArgs.Data.GetData dataFormatsClass.FileDrop
        return queueDroppedFiles droppedFiles
    ),

    fn onDropPanelClick senderObject eventArgs = (
        local fileDialog = dotNetObject "System.Windows.Forms.OpenFileDialog"
        fileDialog.Title = "Select files for Dropper"
        fileDialog.Multiselect = true
        fileDialog.Filter = "Supported files|*.zip;*.rar;*.7z;*.max;*.fbx;*.obj;*.3ds;*.iges;*.igs;*.skp;*.dwg;*.dae;*.stl;*.abc;*.dxf;*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp;*.gif;*.tga;*.exr;*.hdr|All files|*.*"
        if (fileDialog.ShowDialog() == (dotNetClass "System.Windows.Forms.DialogResult").OK) do (
            return processDroppedFiles fileDialog.FileNames
        )
        return false
    ),

    fn loadDropPanelImage = (
        local imageFilePath = scriptFolderPath + "assets\\drop-zone-banner-active.png"
        local sourceImage = undefined
        local loadedImage = undefined
        if (not (dotNetClass "System.IO.File").Exists imageFilePath) do return undefined
        try (
            sourceImage = (dotNetClass "System.Drawing.Image").FromFile imageFilePath
            loadedImage = dotNetObject "System.Drawing.Bitmap" sourceImage
        ) catch (
            loadedImage = undefined
        )
        if (sourceImage != undefined) do try (sourceImage.Dispose()) catch()
        return loadedImage
    ),

    fn buildMainForm = (
        mainForm = dotNetObject "System.Windows.Forms.Form"
        mainForm.Text = "Dropper " + versionContent
        mainForm.FormBorderStyle = (dotNetClass "System.Windows.Forms.FormBorderStyle").FixedToolWindow
        mainForm.ClientSize = dotNetObject "System.Drawing.Size" 330 160
        mainForm.MaximizeBox = false
        mainForm.MinimizeBox = false
        mainForm.ShowInTaskbar = false
        mainForm.TopMost = true
        applyFormTheme mainForm

        dropPanel = dotNetObject "System.Windows.Forms.Panel"
        dropPanel.Location = dotNetObject "System.Drawing.Point" 10 10
        dropPanel.Size = dotNetObject "System.Drawing.Size" 310 88
        dropPanel.AllowDrop = true
        dropPanel.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").None
        dropPanel.BackColor = themeBackgroundColor()
        dropPanel.Cursor = (dotNetClass "System.Windows.Forms.Cursors").Hand
        dropPanelImage = loadDropPanelImage()
        if (dropPanelImage != undefined) do (
            dropPanel.BackgroundImage = dropPanelImage
            dropPanel.BackgroundImageLayout = (dotNetClass "System.Windows.Forms.ImageLayout").Stretch
        )
        mainForm.Controls.Add dropPanel

        statusLabel = dotNetObject "System.Windows.Forms.Label"
        statusLabel.Text = "Ready"
        statusLabel.Location = dotNetObject "System.Drawing.Point" 10 106
        statusLabel.Size = dotNetObject "System.Drawing.Size" 276 20
        statusLabel.ForeColor = themeTextColor()
        mainForm.Controls.Add statusLabel

        local helpButton = dotNetObject "System.Windows.Forms.Button"
        helpButton.Text = "?"
        helpButton.Location = dotNetObject "System.Drawing.Point" 294 102
        helpButton.Size = dotNetObject "System.Drawing.Size" 26 25
        helpButton.TabStop = false
        applyButtonTheme helpButton
        mainForm.Controls.Add helpButton

        local settingsButton = dotNetObject "System.Windows.Forms.Button"
        settingsButton.Text = "Settings"
        settingsButton.Location = dotNetObject "System.Drawing.Point" 10 130
        settingsButton.Size = dotNetObject "System.Drawing.Size" 100 25
        applyButtonTheme settingsButton
        mainForm.Controls.Add settingsButton

        logButton = dotNetObject "System.Windows.Forms.Button"
        logButton.Text = "Show Log"
        logButton.Location = dotNetObject "System.Drawing.Point" 118 130
        logButton.Size = dotNetObject "System.Drawing.Size" 202 25
        applyButtonTheme logButton
        mainForm.Controls.Add logButton

        logBox = dotNetObject "System.Windows.Forms.RichTextBox"
        logBox.Location = dotNetObject "System.Drawing.Point" 10 166
        logBox.Size = dotNetObject "System.Drawing.Size" 310 264
        logBox.ReadOnly = true
        logBox.Multiline = true
        logBox.WordWrap = false
        logBox.ScrollBars = (dotNetClass "System.Windows.Forms.RichTextBoxScrollBars").Both
        logBox.BackColor = themeInputColor()
        logBox.ForeColor = themeTextColor()
        logBox.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").FixedSingle
        logBox.Visible = false
        mainForm.Controls.Add logBox

        dotNet.addEventHandler dropPanel "DragEnter" onDropPanelDragEnter
        dotNet.addEventHandler dropPanel "DragDrop" onDropPanelDragDrop
        dotNet.addEventHandler dropPanel "Click" onDropPanelClick
        dotNet.addEventHandler settingsButton "Click" onSettingsButtonClick
        dotNet.addEventHandler helpButton "Click" onHelpButtonClick
        dotNet.addEventHandler logButton "Click" onToggleLog
        dotNet.addEventHandler mainForm "FormClosing" onMainFormClosing

        restoreWindowPosition()
        return true
    ),

    fn showMainForm = (
        if (isMainFormVisible()) then (
            mainForm.Activate()
            return true
        )
        isCancelRequested = false
        buildMainForm()
        mainForm.Show()
        addLog ("Dropper " + versionContent + " is ready.")
        if (not canWriteSettingsFolder()) do (
            addLog ("Settings folder is not writable: " + scriptFolderPath) severityLevel:3
        )
        return true
    ),

    fn initialize sourceEntryFilePath = (
        entryFilePath = sourceEntryFilePath
        if (entryFilePath == undefined or entryFilePath == "") do (
            throw "Dropper could not determine its script file path."
        )
        scriptFolderPath = normalizeFolderPath ((dotNetClass "System.IO.Path").GetDirectoryName entryFilePath)
        versionContent = resolvePackageVersion()
        iniFilePath = scriptFolderPath + "Dropper.ini"
        loadSettings()
        if (not (dotNetClass "System.IO.File").Exists iniFilePath) do (
            if (not saveSettings()) do (
                throw ("Dropper cannot create settings beside the installed script: " + iniFilePath)
            )
        )
        showMainForm()
        return true
    )
)

try (
    local isDropperAlreadyOpen = false
    if (dropperApp != undefined) do (
        try (isDropperAlreadyOpen = dropperApp.isMainFormVisible()) catch (isDropperAlreadyOpen = false)
    )
    if (isDropperAlreadyOpen) then (
        dropperApp.mainForm.Activate()
    ) else (
        local dropperEntryFilePath = getThisScriptFileName()
        dropperApp = DropperAppManager()
        dropperApp.initialize dropperEntryFilePath
    )
) catch (
    messageBox ("Dropper could not start:\n" + (getCurrentException() as string)) title:"Dropper"
)
