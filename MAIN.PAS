program OSCurse;

uses
    CRT, DOS;

const
    MAX_HEIGHT = 25;
    MAX_WIDTH  = 80;
    MAX_COUNTER = 12;
    FIRST_ITEM = 1;
    BUFFER_DIGIT_SIZE = 12;
    BUFFER_VERSE_SIZE = 15;
    MAX_TIME_SLICE = 2;
    LOCK_TIME = 50;
    NUMBER_OF_SOUND = 28;

procedure CLIENT; forward;
procedure SERVER; forward;

const
    running_line_text : String = 'A: Korolev Anton. W: "Operating systems" ';
    C_FNAME = 'textfile.txt';
    Path = '\lOG_MAIN.txt';

    sound_tones:  array[1..NUMBER_OF_SOUND] of Integer = (500, 0, 600, 0  , 600, 0, 500, 0  ,
    800, 0, 700, 0, 800, 0, 700, 0, 800, 0, 700, 0, 800, 0, 700, 0, 800, 0, 900, 0);
    sound_delays: array[1..NUMBER_OF_SOUND] of Integer = (3, 1, 20, 16, 3, 1, 20, 16,
    3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 16, 10);


type
	Cell = record { Struct video view cell }
		symbol 	: Char;
		attr 	: Byte;
	end;

    Point = record
        x, y : Integer;
    end;

    Size = record
        width, height : Integer;
    end;

    Rect = record
        origin  : Point;
        size    : Size;
    end;

    Frame = record
        x1, y1, x2, y2 : Integer;
    end;

type
	TXTVM = array[1..MAX_HEIGHT, 1..MAX_WIDTH] of Cell; { video video_memory for
                                                            text modes }

	OSAnimatingState = (
		OSAnimatingStateActive,		{ The animation is executing. }
		OSAnimatingStateStopped		{ The animation has been stopped and has not
                                    transitioned to inactive. }
	);

	OSKeyboardTouch = (
		OSKeyboardTouchBegan,	{ whenever a finger touches the surface. }
    	OSKeyboardTouchEnded  	{ whenever a finger leaves the surface. }
	);

    OSQueueState = (
        OSRunning,
        OSSuspended,
        OSCompleted
    );

    OSOperationState = (
        OSActive,
        OSPassive,
        OSStop
    );

type
    Timer = record
        counter         : Integer;  { Количество операций таймера }
        framerate  		: Integer; 	{ Частота кадра }
    end;

	Line = record           { Running line }
        text                : String;
        length              : Integer;
        color               : Byte;
        animationState	    : OSAnimatingState; { состояние анимации }
    	keyboardState      	: OSKeyboardTouch; 	{ состояние анимации }
	end;

    Ticker = record  { Object first task }
        line                : Line;
        timer               : Timer;
        state               : OSOperationState;
        {   /////////////
            /// video settings /// }
        row                 : Integer;
        counter             : Integer;
        insertItemIndex     : Integer; { Element for insert to video streem }
    end;

    Operation = record
        state           : OSOperationState;
        time            : Integer;
    end;

    DigitBuf = record
        buffer                      : array[1..BUFFER_DIGIT_SIZE] of Integer;
        iDx, item, itemIn, itemOut  : Integer;
    end;

    VerseBuf = record
        buffer                      : array[1..BUFFER_VERSE_SIZE] of String[34];
        head, tail                  : Word;
        note                        : Text;
    end;

    Queue = record
        state                       : OSQueueState;
        client, server              : Operation;

        counter                     : Byte; {atomic_counter, thread_life_time}
        excess                      : Integer; {thread_interval_time}
    end;

    Player = record
        iDx, counter, delay           : Integer;
        state                       : OSOperationState;

    end;


var
    _video_memory	    : TXTVM absolute $B800:$0000;
    _ESC                : Boolean;

    _ticker             : Ticker;
    _queue              : Queue;
    _player              : Player;

    _digit              : DigitBuf;
    _verse              : VerseBuf;

    _file               : Text;


    Systime 	: procedure;
    Keyboard 	: procedure;


{ 	////////////////////////////////////////////
	// pragma mark - COMMON //
}

procedure PRINT(const s: String; const x, y, color: Byte);
    var
        i: Integer;

    begin
        for i := x to x + Length(s) - 1 do begin
            _video_memory[y, i].symbol  := s[i - x + 1];
            _video_memory[y, i].attr    := color;
        end;
    end;

function ARM(state: OSOperationState): Integer;
    begin
        case state of
            OSActive: 	ARM := 2;
            OSPassive: 	ARM := 3;
            OSStop: 	ARM := 4;
        end;
    end;

function TXT(state: OSOperationState): String;
    begin
        case state of
            OSActive:  	TXT := 'Active';
            OSPassive: 	TXT := 'Passive';
            OSStop: 	TXT := 'Stop';
        end;
    end;

function BUFFER: String;
    begin
        if _digit.iDx <= 0 then begin
            BUFFER := '- buffer is empty';
        end else if _digit.iDx >= BUFFER_DIGIT_SIZE then begin
            BUFFER := '- buffer is full';
        end else begin
            BUFFER := ' ';
        end;
    end;

procedure DRAW_RUNNING_LINE;
    begin
        Window(29, 4, 37, 6);
        TextBackground(Black);
        TextColor(White);
        ClrScr;

        GotoXY(1, 1);

        if _ticker.row = 1 then begin
            WriteLn('UP');
        end else begin
            WriteLn('DOWN');
        end;

        Write(_ticker.timer.framerate);
    end;

procedure DRAW_CONTROLL;
    begin
        { Border }
        Window(2, 2, 38, 24);
        TextBackground(White);
        TextColor(Black);
        ClrScr;

        GotoXY(10, 1);
        Write('::: CONTROLS :::'); { 16 pt}

        { Body }
        { 24 - 10 }
        Window(3, 3, 37, 23);
        TextBackground(Black);
        TextColor(White);
        ClrScr;

        { --- --- --- --- --- --- Operations --- --- --- --- --- --- }
        Window(3, 3, 37, 4);
        TextBackground(Brown);
        TextColor(White);
        ClrScr;

        GoToXY(11, 1);
        Write('TASKS STATES'); { 12 pt }

        Window(3, 4, 37, 8); { FRAME OPERATIONS }
        TextBackground(Black);
        TextColor(White);
        ClrScr;

        GotoXY(1, 1);
        WriteLn('F1 Running line        :'); { 24 pt }
        WriteLn('F2 Music               :');
        WriteLn('F3 Client              :');
        Write('F4 Server              :');

        { --- --- --- --- --- --- Buffers --- --- --- --- --- --- }
        Window(3, 8, 37, 9);
        TextBackground(Brown);
        TextColor(White);
        ClrScr;

        GoToXY(11, 1);
        Write('THREAD STATE'); { 12 pt }

        Window(3, 9, 37, 13); { FRAME BUFFER }
        TextBackground(Black);
        TextColor(White);
        ClrScr;

        GoToXY(1, 1);
        writeLn('F5 / F6 Client time    :');
        writeLn('F7 / F8 Server time    :');
        WriteLn('Digit buffer level     :');
        Write('Verse buffer level     :');

        { --- --- --- --- --- --- Running line --- --- --- --- --- --- }
        Window(3, 13, 37, 14);
        TextBackground(Brown);
        TextColor(White);
        ClrScr;

        GoToXY(11, 1);
        Write('RUNNING LINE'); { 12 pt }

        Window(3, 14, 37, 16); { FRAME RUNNING LINE }
        TextBackground(Black);
        TextColor(White);
        ClrScr;

        GotoXY(1, 1);
        WriteLn('Q   Swap location      :');
        Write('+/- Change speed       :');

        { --- --- --- --- --- --- Common --- --- --- --- --- --- }
        Window(3, 16, 37, 17);
        TextBackground(Brown);
        TextColor(White);
        ClrScr;

        GoToXY(14, 1);
        Write('COMMON'); { 6 pt }

        Window(3, 17, 37, 18); { FRAME RUNNING LINE }
        TextBackground(Black);
        TextColor(White);
        ClrScr;

        GoToXY(1, 1);
        Write('Esc - exit             :');
    end;

procedure LOGG(s : String);
    begin
        Append(_file);
    	Writeln(_file, s);
    	Close(_file);
    end;

{ 	////////////////////////////////////////////
	// pragma mark - RUNNING_LINE //
}

procedure TICKER_INIT;
    var
       i : Integer;

    begin
        _ticker.timer.framerate := 2;
        _ticker.timer.counter := 0;

        _ticker.line.animationState := OSAnimatingStateActive;
        _ticker.line.keyboardState  := OSKeyboardTouchEnded;
        _ticker.line.text           := running_line_text;
        _ticker.line.color          := White;
        _ticker.line.length         := Length(running_line_text);

        _ticker.insertItemIndex := FIRST_ITEM;
        _ticker.counter := FIRST_ITEM;
        _ticker.state := OSActive;
    end;

procedure TICKER_DRAW;
    var
        y, x, idx, counter: Integer;
        text : String;
        color : Byte;

    begin
        color   := _ticker.line.color;
        text    := _ticker.line.text;

        y       := _ticker.row;
        idx     := _ticker.insertItemIndex;
        counter := _ticker.counter;

        for x := 1 to MAX_WIDTH - 1 do begin
            _video_memory[y, x] := _video_memory[y, x + 1];
        end;

        x := MAX_WIDTH;

        if ( idx <= _ticker.line.length ) then begin
            _video_memory[y, x].symbol   := text[idx];
            _video_memory[y, x].attr     := color;
            inc(idx);
        end else if ( counter > MAX_WIDTH ) then begin
            idx := FIRST_ITEM;
            counter := FIRST_ITEM;
        end else begin
            _video_memory[y, x].symbol   := ' ';
            _video_memory[y, x].attr     := color;
            inc(counter);
        end;

        _ticker.insertItemIndex := idx;
        _ticker.counter := counter;
    end;

procedure TIME_TICKER_HANDLER;
    var
        framerate : Integer;

    begin
        framerate   := _ticker.timer.framerate;

        case _ticker.state of
			OSActive: begin
    			inc(_ticker.timer.counter);
    			if _ticker.timer.counter >= MAX_COUNTER - framerate then begin
    				TICKER_DRAW;
    				_ticker.timer.counter := 0;
    			end;
			end;
		end;
    end;

{ 	////////////////////////////////////////////
	// pragma mark - Two streams //
}

{ Проверка очереди на заполненноoтo }
function FULL: Boolean;
    begin
        if _verse.tail < _verse.head then begin
            FULL := _verse.tail + 1 = _verse.head;
        end;

        FULL := (_verse.head = 1) and (_verse.tail = BUFFER_VERSE_SIZE);
    end;

    { Добавление элемента в очередь }
procedure ENQUEUE(Const X: String);
    begin
        _verse.buffer[_verse.tail] := X;

        if _verse.tail < BUFFER_VERSE_SIZE then begin
            Inc(_verse.tail);
        end else begin
            _verse.tail := 1;
        end;
    end;

    { Извлечение oлемента из очереди }
function DEQUEUE: String;
    var
        head : Word;
    begin
        head := _verse.head;
        if _verse.head < BUFFER_VERSE_SIZE then begin
            Inc(_verse.head);
        end else begin
            _verse.head := 1
        end;

        DEQUEUE := _verse.buffer[_verse.head];
    end;

    { Проверка очереди на пуoтоту }
function EMPTY: Boolean;
    begin
        EMPTY := _verse.head = _verse.tail;
    end;

    { Возвращает чиoло oлементов очереди }
function COUNT: Word;
    begin
        if _verse.tail < _verse.head then begin
            COUNT := BUFFER_VERSE_SIZE - _verse.head + _verse.tail;
        end else begin
            COUNT := _verse.tail - _verse.head;
        end;
    end;

{ /////////////////////// }

function CAN_PERFORM(const t: Integer): Boolean;
    begin
        CAN_PERFORM := _queue.counter < t + _queue.excess;
    end;

function FEATURE(x: Integer): Boolean;
	begin
		FEATURE := sqrt(x) = round(sqrt(x));
	end;

function LVLBUF: Real;
    begin
        LVLBUF := _digit.iDx / BUFFER_DIGIT_SIZE;
    end;

procedure QUEUE_DRAW;
    var
        i: Integer;
        x1, y1, x2, y2 : Integer;
        serverInf, clientInf: String;
        serverArm, clientArm: Integer;

    begin
        serverInf   := TXT(_queue.server.state); { Цвет }
        serverArm 	:= ARM(_queue.server.state); { Состояние }
        clientInf   := TXT(_queue.client.state);
        clientArm 	:= ARM(_queue.client.state);

        x1 := (MAX_WIDTH div 2 );
        y1 := 2;
        x2 := MAX_WIDTH;
        y2 := (MAX_HEIGHT div 2) - y1;

        Window(x1, y1, x2, y2);
        TextBackground(White);
        textColor(Black);
        ClrScr;

        write('SERVER: ', _digit.itemIn:3, ' > ');
        textColor(serverArm);
        write(serverInf:7);
        writeln;

        write('CLIENT: ', _digit.itemOut:3, ' > ');
        textColor(clientArm);
        write(clientInf:7);
        writeln;
        writeln;

        for i := 1 to _digit.iDx do begin
            write(_digit.buffer[i], ' ');
        end;

        writeln;
        writeln;

        writeln('BUFFER: ', round(LVLBUF * 100), ' %', BUFFER);
        writeln;
    end;

procedure QUEUE_INIT;
    begin
        _queue.state            := OSRunning;

        _queue.server.state     := OSPassive;
        _queue.server.time      := 20;

		_queue.client.state     := OSPassive;
        _queue.client.time      := 13;

		_digit.item       := -1;
		_digit.itemIn     := 0;
		_digit.itemOut    := 0;
		_digit.iDx        := 0;

        _verse.tail := 1;
        _verse.head := 1;
    end;

procedure CLIENT;
    var
        i, j: Integer;
        s: String[8];
        story: String[34];

    begin
        _queue.counter := 0;
        while CAN_PERFORM(_queue.client.time) and (_queue.client.state <> OSStop) do begin
            _queue.client.state := OSActive;
            if _digit.iDx > 0 then begin
                _digit.itemOut := _digit.buffer[_digit.iDx];
                Dec(_digit.iDx);
            end else begin
                _queue.client.state := OSPassive;
            end;

            if not EMPTY then begin
                story := DEQUEUE;
                for i := 13 to 23 do begin
                    for j := 41 to 78 do begin
                        _video_memory[i, j].symbol := _video_memory[i + 1, j].symbol;
                        _video_memory[i, j].attr   := _video_memory[i + 1, j].attr;
                    end;
                end;

                for  i := 41 to 78 do begin
                    _video_memory[23, i].symbol := ' ';
                end;

                PRINT(story, 41, 23, White);
                { вывести буффер }

            end else begin
                _queue.client.state := OSPassive;
            end;

            if _queue.client.state = OSPassive then begin
                _queue.excess := _queue.client.time + _queue.excess - _queue.counter;
                SERVER;
                Exit;
            end;

            QUEUE_DRAW;
            Delay(LOCK_TIME);
        end;

        _queue.client.state := OSPassive;
        _queue.excess := 0;
    end;

procedure SERVER;
    var
    	story: String[34];
        s: String[8];

    begin
        _queue.counter := 0;
        while CAN_PERFORM(_queue.server.time) and (_queue.server.state <> OSStop) do begin
            _queue.server.state := OSActive;

            if _digit.iDx < BUFFER_DIGIT_SIZE then begin
                repeat
                    inc(_digit.item);
                until FEATURE(_digit.item);

                _digit.itemIn := _digit.item;
                inc(_digit.iDx);
                _digit.buffer[_digit.iDx] := _digit.item;
            end	else begin
                _queue.server.state := OSPassive;
            end;

            if not FULL then begin
                if EOF(_verse.note) then begin
                    Reset(_verse.note);
                end else begin
                    read(_verse.note, story);
                end;

                while Length(story) < 34 do begin
                    story := story + ' ';
                end;

                ENQUEUE(story);
                { вывод процентов }

            end else begin
                _queue.server.state := OSPassive;
            end;


            if _queue.server.state = OSPassive then begin
                _queue.excess := _queue.server.time + _queue.excess - _queue.counter;
                CLIENT;
                Exit;
            end;

            QUEUE_DRAW;
            Delay(LOCK_TIME);
        end;

        _queue.server.state := OSPassive;
        _queue.excess := 0;
    end;

procedure RUN_LOOP;
    begin
        Randomize;
        while Not _ESC do begin
            case Random(MAX_TIME_SLICE) + 1 of
                1: SERVER;
                2: CLIENT;
            end;
        end;
    end;

procedure TIME_QUEUE_HANDLER;
    begin
        Inc(_queue.counter);
    end;

{ 	////////////////////////////////////////////
	// pragma mark - SOUND //
}

procedure SOUND_INIT;
    begin
        _player.iDx := 0;
        _player.state := OSActive;
        _player.counter := 0;
        _player.delay := 0;
    end;

procedure PLAY_SOUND;
    var
        signal : Integer;

    begin
        _player.counter := 0;

        if _player.iDx < NUMBER_OF_SOUND then begin
            Inc(_player.iDx);

            signal := sound_tones[_player.iDx];
            _player.delay := sound_delays[_player.iDx];

            if signal = 0 then begin
                Nosound;
            end else begin
                Sound(signal);
            end;
        end else begin
            _player.iDx := 0;
        end;
    end;

procedure RUN_SOUND;
    begin
        if _player.counter >= _player.delay then begin
            PLAY_SOUND;
        end else begin
            Inc(_player.counter);
        end;
    end;

procedure TIME_SOUND_HANDLER;
    begin
        if _player.state = OSActive then begin
            RUN_SOUND;
        end else begin
            NoSound;
        end;
    end;

{ 	////////////////////////////////////////////
	// pragma mark - INTERRUPT //
}

{ $F+ }
procedure TimeHandler; interrupt;
	begin
        TIME_TICKER_HANDLER;
        TIME_QUEUE_HANDLER;
        TIME_SOUND_HANDLER;

		inline($09C);
		Systime;
	end;
{ $F- }

{ $F+ }
procedure KeyboadrHandler; interrupt;
    var
        tmp : String;
        x, y, dy, framerate : Integer;
    begin
        case port[$60] of
            1: begin
                _ESC := True;
            end;

            12: begin
                framerate := _ticker.timer.framerate;
                if framerate > 1 then begin
                    Dec(framerate);
                    _ticker.timer.framerate := framerate;
                    DRAW_RUNNING_LINE;
                end;
            end;

            13: begin
                framerate := _ticker.timer.framerate;
                if framerate < MAX_COUNTER then begin
                    Inc(framerate);
                    _ticker.timer.framerate := framerate;
                    DRAW_RUNNING_LINE;
                end;
            end;

            16: begin
                _ticker.line.keyboardState := OSKeyboardTouchBegan;
                dy := _ticker.row;

                if _ticker.row = 1 then begin
                    y := MAX_HEIGHT;
                end else begin
                    y := 1;
                end;

                for x := 1 to MAX_WIDTH do begin
                    _video_memory[y, x] := _video_memory[dy, x];
                    _video_memory[dy, x].symbol   := ' ';
                    _video_memory[dy, x].attr     := Black;
                end;

                _ticker.row := y;
                _ticker.line.keyboardState := OSKeyboardTouchEnded;
                DRAW_RUNNING_LINE;
            end;

        end;

        if port[$60] = 16 then begin

        end;

        Str(port[$60], tmp);
        LOGG(tmp);

        inline($90C);
		Keyboard;
    end;
{ $F- }

{ 	////////////////////////////////////////////
	// pragma mark - KEYBOARD //
}

procedure ARGC; { Processing the input arguments }
    var
        file_name       : String;
        line_side       : String;
        error_code      : Integer;

    begin
        {
        if ParamCount <> 2 then
            begin
                writeLn('Error: You have entered the ', ParamCount);
                write('parameters. You need to specify two parameters. ');
                writeLn('First: Name of file .txt for display text.');
                writeLn('Second: Running line next to up or down screen side.');
                readln;
            end;

        file_name := ParamStr(1);
        line_side := ParamStr(2);

        if Not (line_side[1] In ['D', 'U', 'd', 'u']) then begin
            writeLn('Entering screen side wrong');
            readln;
        end;
                     }
        {Assign(_file_text, file_name); { Assign a name to a file }
        {Reset(_file_text); { Open file for reading }

        _ticker.insertItemIndex := FIRST_ITEM;
        _ticker.row := 1;

    end;

procedure DRAW; { Render the view }
    begin
        {0, 0, 80, 25}
        TextBackground(Black); { Background color }
        TextColor(Black);
        ClrScr; { Clear all sumbols }

        DRAW_CONTROLL;
    end;

procedure INIT; { Setting the property }
    begin
        TICKER_INIT;
        QUEUE_INIT;
        SOUND_INIT;

        _ESC := False;
    end;

Procedure SetCursorSize(Const BegLine, EndLine: Byte);
    Var
        Regs: Registers;
    Begin
        With Regs Do Begin
            AH := $01;
            CH := BegLine;
            CL := EndLine;
        End;
        Intr($10, Regs);
    End;

BEGIN
    Assign(_file, Path); {assign a text file}
    ReWrite(_file);
    WriteLn('LOG FILE PASCAL PROGRAMMING:');
    WriteLn(' ');
    Close(_file);

    GotoXY(1, MAX_HEIGHT);
    SetCursorSize($06, $07);



    ARGC;
    INIT;
    DRAW;

    SetCursorSize($20, $00);

    Assign(_verse.note, '1.txt');
    Reset(_verse.note);

    GetIntVec($8, @Systime);
    SetIntVec($8, Addr(TimeHandler));

    GetIntVec($9, @Keyboard);
    SetIntVec($9, Addr(KeyboadrHandler));

    RUN_LOOP;

    SetCursorSize($06, $07);
    Window(1, 1, MAX_WIDTH, MAX_HEIGHT);
    TextBackground(Black);
    TextColor(White);
    GotoXY(1, MAX_HEIGHT);
    ClrScr;

    Nosound;
    SetIntVec($8, Addr(Systime));
    SetIntVec($9, Addr(Keyboard));

END.
