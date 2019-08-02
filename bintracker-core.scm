;; -*- geiser-scheme-implementation: 'chicken -*-

;; This file is part of Bintracker NG.
;; Copyright (c) utz/irrlicht project 2019
;; See LICENSE for license details.

(module bintracker-core
    *

  (import scheme (chicken base) (chicken platform) (chicken string)
	  (chicken module) (chicken io) (chicken bitwise) (chicken format)
	  srfi-1 srfi-13 srfi-69 pstk defstruct matchable
	  simple-exceptions mdal bt-state bt-types bt-gui)
  ;; all symbols that are required in generated code (mdal compiler generator)
  ;; must be re-exported
  (reexport mdal pstk bt-types bt-state bt-gui (chicken bitwise)
	    srfi-1 srfi-13 simple-exceptions)


  ;; ---------------------------------------------------------------------------
  ;;; # Initialize Global State and Settings
  ;; ---------------------------------------------------------------------------

  ;; init pstk and fire up Tcl/Tk runtime.
  ;; This must be done prior to defining anything that depends on Tk.
  (tk-start)
  (tk-eval "option add *tearOff 0")
  (ttk-map-widgets '(button checkbutton radiobutton menubutton label frame
			    labelframe scrollbar notebook panedwindow
			    progressbar combobox separator scale sizegrip
			    spinbox treeview))

  ;; Load config file
  (handle-exceptions
      exn
      (begin
	(display exn)
	(newline))
      ;; #f ;; TODO: ignoring config errors is fine, but actually report errors
    (load "config/config.scm"))


  ;; ---------------------------------------------------------------------------
  ;;; # GUI
  ;; ---------------------------------------------------------------------------

  (define (about-message)
    (tk/message-box title: "About"
		    message: (string-append "Bintracker\nversion "
					    *bintracker-version*)
		    type: 'ok))

  ;;; Display a message box that asks the user whether to save unsaved changes
  ;;; before exiting or closing. **exit-or-closing** should be the string
  ;;; `"exit"` or `"closing"`, respectively.
  (define (exit-with-unsaved-changes-dialog exit-or-closing)
    (tk/message-box title: (string-append "Save before " exit-or-closing "?")
		    default: 'yes
		    icon: 'warning
		    parent: tk
		    message: (string-append "There are unsaved changes. "
					    "Save before " exit-or-closing "?")
		    type: 'yesnocancel))

  (define (do-proc-with-exit-dialogue dialogue-string proc)
    (if (state 'modified)
	(match (exit-with-unsaved-changes-dialog dialogue-string)
	  ("yes" (begin (save-file)
			(proc)))
	  ("no" (proc))
	  (else #f))
	(proc)))

  (define (exit-bintracker)
    (do-proc-with-exit-dialogue "exit" tk-end))

  ;; TODO disable menu option
  (define (close-file)
    (when (current-mod)
      (do-proc-with-exit-dialogue
       "closing"
       (lambda ()
	 (destroy-group-widget (state 'module-widget))
	 (reset-state!)
	 (set-play-buttons 'disabled)
	 (update-window-title!)
	 (update-status-text)))))

  (define (load-file)
    (let ((filename (tk/get-open-file
		     filetypes: '{{{MDAL Modules} {.mdal}} {{All Files} *}})))
      (unless (string-null? filename)
	(begin (console 'insert 'end
			       (string-append "\nLoading file: " filename "\n"))
	       (handle-exceptions
		   exn
		   (console 'insert 'end
			    (string-append "\nError: " (->string exn)
					   "\n" (message exn)))
		 (set-current-mod! filename)
		 (set-state! 'current-file filename)
		 (set-state! 'module-widget (make-module-widget main-frame))
		 (show-module)
		 (set-play-buttons 'enabled)
		 (update-status-text)
		 (update-window-title!))))))

  (define (save-file)
    (if (state 'current-file)
	(md:module->file (current-mod) (state 'current-file))
	(save-file-as))
    (set-state! 'modified #f)
    (update-window-title!))

  (define (save-file-as)
    (let ((filename (tk/get-save-file
		     filetypes: '(((MDAL Modules) (.mdal)))
		     defaultextension: '.mdal)))
      (unless (string-null? filename)
	(md:module->file (current-mod) filename)
	(set-state! 'current-file filename)
	(set-state! 'modified #f)
	(update-window-title!))))

  (define (launch-help)
    ;; TODO windows untested
    (let ((uri (cond-expand
		 (unix "\"documentation/index.html\"")
		 (windows "\"documentation\\index.html\"")))
	  (open-cmd (cond-expand
		      ((or linux freebsd netbsd openbsd) "xdg-open ")
		      (macosx "open ")
		      (windows "[list {*}[auto_execok start] {}] "))))
      (tk-eval (string-append "exec {*}" open-cmd uri " &"))))

  (define (tk/icon filename)
    (tk/image 'create 'photo format: "PNG"
	      file: (string-append "resources/icons/" filename)))


  ;; ---------------------------------------------------------------------------
  ;;; ## Main Menu
  ;; ---------------------------------------------------------------------------

  (define (init-main-menu)
    (set-state!
     'menu (construct-menu
	    (map (lambda (item) (cons 'submenu item))
		 `((file "File" 0 ((command new "New..." 0 "Ctrl+N" #f)
				   (command open "Open..." 0 "Ctrl+O"
					    ,load-file)
				   (command save "Save" 0 "Ctrl+S" ,save-file)
				   (command save-as "Save as..." 5
					    "Ctrl+Shift+S" ,save-file-as)
				   (command close "Close" 0 "Ctrl+W"
					    ,close-file)
				   (separator)
				   (command exit "Exit" 1 "Ctrl+Q"
					    ,exit-bintracker)))
		   (edit "Edit" 0 ())
		   (generate "Generate" 0 ())
		   (transform "Transform" 0 ())
		   (help "Help" 0 ((command launch-help "Help" 0 "F1"
					    ,launch-help)
				   (command about "About" 0 #f
					    ,about-message))))))))


  ;; ---------------------------------------------------------------------------
  ;;; ## Top Level Layout
  ;; ---------------------------------------------------------------------------

  (define top-frame (tk 'create-widget 'frame 'padding: "0 0 0 0"))

  (define toolbar-frame (top-frame 'create-widget 'frame 'padding: "0 1 0 1"))

  (define edit-settings-frame (top-frame 'create-widget 'frame))

  (define main-panes (top-frame 'create-widget 'panedwindow))

  (define main-frame (main-panes 'create-widget 'frame))

  (define console-frame (main-panes 'create-widget 'frame))

  (define status-frame (top-frame 'create-widget 'frame))

  (define (init-top-level-layout)
    (begin
      (tk/pack status-frame fill: 'x side: 'bottom)
      (tk/pack top-frame expand: 1 fill: 'both)
      (tk/pack toolbar-frame expand: 0 fill: 'x)
      (tk/pack (top-frame 'create-widget 'separator orient: 'horizontal)
	       expand: 0 fill: 'x)
      (show-edit-settings)
      (tk/pack edit-settings-frame expand: 0 'fill: 'x)
      (tk/pack main-panes expand: 1 fill: 'both)
      (main-panes 'add main-frame weight: 5)
      (main-panes 'add console-frame weight: 2)))


  ;; ---------------------------------------------------------------------------
  ;;; ## Status Bar
  ;; ---------------------------------------------------------------------------

  (define status-text (status-frame 'create-widget 'label))

  (define (update-status-text)
    (let ((status-msg (if (current-mod)
			  (string-append
			   (md:target-id
			    (md:config-target (current-config)))
			   " | "
			   (md:mod-cfg-id (current-mod)))
			  "No module loaded.")))
      (status-text 'configure 'text: status-msg)))

  (define (init-status-bar)
    (begin (tk/pack status-text fill: 'x side: 'left)
	   (tk/pack (status-frame 'create-widget 'sizegrip) side: 'right)
	   (update-status-text)))


  ;; ---------------------------------------------------------------------------
  ;;; ## Toolbar
  ;; ---------------------------------------------------------------------------

  (define (toolbar-button icon command #!optional (init-state 'disabled))
    (toolbar-frame 'create-widget 'button image: (tk/icon icon)
		   state: init-state
		   command: command
		   style: "Toolbutton"))

  (define button-new (toolbar-button "new.png" (lambda () #t) 'enabled))
  (define button-load (toolbar-button "load.png" load-file 'enabled))
  (define button-save (toolbar-button "save.png" (lambda () #t)))
  (define button-undo (toolbar-button "undo.png" (lambda () #t)))
  (define button-redo (toolbar-button "redo.png" (lambda () #t)))
  (define button-copy (toolbar-button "copy.png" (lambda () #t)))
  (define button-cut (toolbar-button "cut.png" (lambda () #t)))
  (define button-clear (toolbar-button "clear.png" (lambda () #t)))
  (define button-paste (toolbar-button "paste.png" (lambda () #t)))
  (define button-insert (toolbar-button "insert.png" (lambda () #t)))
  (define button-swap (toolbar-button "swap.png" (lambda () #t)))
  (define button-stop (toolbar-button "stop.png" (lambda () #t)))
  (define button-play (toolbar-button "play.png" (lambda () #t)))
  (define button-play-from-start (toolbar-button "play-from-start.png"
						 (lambda () #t)))
  (define button-play-ptn (toolbar-button "play-ptn.png" (lambda () #t)))
  (define button-prompt (toolbar-button "prompt.png" (lambda () #t) 'enabled))
  (define button-settings (toolbar-button "settings.png" (lambda () #t)
					  'enabled))

  (define (make-toolbar)
    (let ((make-separator (lambda ()
			    (toolbar-frame 'create-widget 'separator
					   orient: 'vertical))))
      (map (lambda (elem)
	     ;; TODO pad seperators, but nothing else
	     (tk/pack elem side: 'left padx: 0 fill: 'y))
	   (list button-new button-load button-save (make-separator)
		 button-undo button-redo (make-separator)
		 button-copy button-cut button-clear button-paste
		 button-insert button-swap (make-separator)
		 button-stop button-play button-play-from-start
		 button-play-ptn (make-separator)
		 button-settings button-prompt))))

  (define (set-play-buttons state)
    (map (lambda (button)
	   (button 'configure state: state))
	 (list button-stop button-play button-play-from-start
	       button-play-ptn)))

  ;; ---------------------------------------------------------------------------
  ;;; ## Edit Settings Display
  ;; ---------------------------------------------------------------------------

  (define (show-edit-settings)
    (letrec* ((edit-step-label (edit-settings-frame 'create-widget 'label
						    text: "Edit Step"))
	      (base-octave-label (edit-settings-frame 'create-widget 'label
						      text: "Base Octave"))
	      (edit-step-spinbox
	       (edit-settings-frame
		'create-widget 'spinbox from: 0 to: 64 validate: 'focusout
		validatecommand:
		(lambda ()
		  (let* ((newval (string->number (edit-step-spinbox 'get)))
			 (valid? (and (integer? newval)
				      (>= newval 0)
				      (<= newval 64))))
		    (when valid? (set-state! 'edit-step newval))
		    valid?))
		invalidcommand:
		(lambda ()
		  (edit-step-spinbox 'set (state 'edit-step)))))
	      (base-octave-spinbox
	       ;; TODO validation
	       (edit-settings-frame 'create-widget 'spinbox from: 0 to: 9
				    state: 'disabled)))
      (tk/pack edit-step-label side: 'left padx: 5)
      (tk/pack edit-step-spinbox side: 'left)
      (tk/pack (edit-settings-frame 'create-widget 'separator orient: 'vertical)
	       side: 'left fill: 'y)
      (tk/pack base-octave-label side: 'left padx: 5)
      (tk/pack base-octave-spinbox side: 'left)
      (edit-step-spinbox 'set 1)
      (base-octave-spinbox 'set 4)))

  ;; ---------------------------------------------------------------------------
  ;;; ## Console
  ;; ---------------------------------------------------------------------------

  (define console-wrapper (console-frame 'create-widget 'frame))

  ;; TODO color styling should be done in bt-state or bt-gui
  (define console (console-wrapper 'create-widget 'text blockcursor: 'yes))

  (define console-yscroll (console-wrapper 'create-widget 'scrollbar
					   orient: 'vertical))

  (define (eval-console)
    (handle-exceptions
	exn
	(console 'insert 'end
			(string-append "\nError: " (->string exn)
				       (->string (arguments exn))))
      (let ((input-str (console 'get "end-1l" "end-1c")))
	(when (not (string-null? input-str))
	  (console 'insert 'end
			  (string-append
			   "\n"
			   (->string
			    (eval (read (open-input-string input-str))))))))))

  (define (init-console)
    (tk/pack console-wrapper expand: 1 fill: 'both)
    (tk/pack console expand: 1 fill: 'both side: 'left)
    (tk/pack console-yscroll side: 'right fill: 'y)
    (console-yscroll 'configure command: `(,console yview))
    (console 'configure 'yscrollcommand: `(,console-yscroll set))
    (console 'insert 'end
	     (string-append "Bintracker " *bintracker-version*
			    "\n(c) 2019 utz/irrlicht project\n"
			    "Ready.\n")))


  ;; ---------------------------------------------------------------------------
  ;;; ## Key Bindings
  ;; ---------------------------------------------------------------------------

  (define (update-key-bindings!)
    (for-each (lambda (group widget)
		(for-each (lambda (key-mapping)
			    (tk/bind widget (car key-mapping)
				     (eval (cadr key-mapping))))
			  (get-keybinding-group group)))
	      '(global console)
	      (list tk console)))


  ;; ---------------------------------------------------------------------------
  ;;; Style updates
  ;; ---------------------------------------------------------------------------

    ;; TODO also update other metawidget colors here
  (define (update-style!)
    (ttk/style 'configure 'Metatree.Treeview background: (colors 'row)
	       fieldbackground: (colors 'row)
	       foreground: (colors 'text)
	       font: (list family: (settings 'font-mono)
			   size: (settings 'font-size))
	       rowheight: (get-treeview-rowheight))
    ;; hide treeview borders
    (ttk/style 'layout 'Metatree.Treeview '(Treeview.treearea sticky: nswe))
    ;; FIXME still doesn't hide the indicator
    (ttk/style 'configure 'Metatree.Treeview.Item indicatorsize: 0)

    (ttk/style 'configure 'BT.TFrame background: (colors 'row))

    (ttk/style 'configure 'BT.TLabel background: (colors 'row)
	       foreground: (colors 'text)
	       font: (list family: (settings 'font-mono)
			   size: (settings 'font-size)
			   weight: 'bold))

    (ttk/style 'configure 'BT.TNotebook background: (colors 'row))
    (ttk/style 'configure 'BT.TNotebook.Tab
	       background: (colors 'row)
	       font: (list family: (settings 'font-mono)
			   size: (settings 'font-size)
			   weight: 'bold))

    ;; TODO console is defined in core, but needs to be known here
    ;; or move update-style! to bt-gui
    (console 'configure bg: (colors 'console-bg))
    (console 'configure fg: (colors 'console-fg))
    (console 'configure insertbackground: (colors 'console-fg))
    )



  ;; ---------------------------------------------------------------------------
  ;;; # Startup Procedure
  ;; ---------------------------------------------------------------------------

  ;;; WARNING: YOU ARE LEAVING THE FUNCTIONAL SECTOR!

  (update-window-title!)
  (update-style!)

  ;; (init-menu)
  (init-main-menu)
  (when (settings 'show-menu)
    (tk 'configure 'menu: (menu-widget (state 'menu))))

  (init-top-level-layout)
  (when (app-settings-show-toolbar *bintracker-settings*) (make-toolbar))
  (init-console)
  (init-status-bar)
  (update-key-bindings!)

  ;; ---------------------------------------------------------------------------
  ;;; # Main Loop
  ;; ---------------------------------------------------------------------------

  (tk-event-loop)

  ) ;; end module bintracker
