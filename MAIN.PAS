program OSCurse;

uses
    CRT, DOS;

const
    MAX_HEIGHT = 25;
    MAX_WIDTH  = 80;
    MAX_COUNTER = 12;
    FIRST_ITEM = 1;
    BUFFER_SIZE = 78;
    MAX_TIME_SLICE = 2;
    LOCK_TIME = 50;

procedure CLIENT; forward;
procedure SERVER; forward;

const
    running_line_text : String = 'A: Korolev Anton. W: "Operating systems" ';
    C_FNAME = 'textfile.txt';
    Path = '\lOG_MAIN.txt';

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

        {   /////////////
            /// video settings /// }
        row                 : Integer;
        counter             : Integer;
        insertItemIndex     : Integer; { Element for insert to video streem }
    end;

    Operation = record
        state           : OSOperationState;
    end;

    Queue = record
        state                       : OSQueueState;
        buffer                      : array[1..BUFFER_SIZE] of Integer;
        client, server              : Operation;
        iDx, item, itemIn, itemOut  : Integer;

        counter, time               : Byte; {atomic_counter, thread_life_time}
        excess                      : Integer; {thread_interval_time}
    end;


var
    _video_memory	    : TXTVM absolute $B800:$0000;
    _ESC                : Boolean;

    _ticker             : Ticker;
    _queue              : Queue;


    _file               : Text;


    Systime 	: procedure;
    Keyboard 	: procedure;


{ 	////////////////////////////////////////////
	// pragma mark - COMMON //
}

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
        if _queue.iDx <= 0 then begin
            BUFFER := '- buffer is empty';
        end else if _queue.iDx >= BUFFER_SIZE then begin
            BUFFER := '- buffer is full';
        end else begin
            BUFFER := ' ';
        end;
    end;

procedure DRAW_CONTROLL;
    var
        x1, y1, x2, y2 : Integer;
        l, s : String;

    begin
        { Border }
        x1 := 2;
        y1 := 2;
        x2 := (MAX_WIDTH div 2 ) - x1;
        y2 := MAX_HEIGHT - y1;

        Window(x1, y1, x2, y2);
        TextBackground(White);
        ClrScr;

        TextColor(Black);
        GotoXY(x1, 1);
        Write('INDICATORS ');

        { Body }
        x1 := x1 + 1;
        y1 := y1 + 1;
        x2 := (MAX_WIDTH div 2 ) - x1;
        y2 := MAX_HEIGHT - y1;

        { Running line }
        Window(x1, y1, x2, y1 + 1);
        TextBackground(Brown);
        ClrScr;

        TextColor(White);
        GoToXY(((x2 - x1) div 2) - 2, 1);
        Write('LINE');

        Window(x1, y1 + 1, x2, y2);
        TextBackground(Blue);
        ClrScr;

        if _ticker.row = 1 then begin
            l := 'Up';
        end else begin
            l := 'Down'
        end;

        TextColor(Yellow);
        GotoXY(1, 1);
        Write('Q - Swap location: ');
        TextColor(Green);
        Write(l);

        TextColor(Yellow);
        GoToXY(1, 2);
        Write('+/- Change speed: ');
        TextColor(Green);
        Write(_ticker.timer.framerate);

        { Thread }
        y1 := y1 + 3;

        Window(x1, y1, x2, y1);
        TextBackground(Brown);
        ClrScr;

        TextColor(White);
        GoToXY(((x2 - x1) div 2) - 2, 1);
        Write('THREAD');

        TextColor(Yellow);
        GoToXY(1, 2);
        WriteLn('F1 SERVER: ');
        Write('F2 CLIENT: ');

    end;

procedure LOGG(s : String);
    begin
        Append(_file);
    	Writeln(_file, s);
    	Close(_file);
    end;

function StringFromRect(r : Rect): String;
    var
        s, tmp : String;

    begin
        s := 'Rect(x = ';
        Str(r.origin.x, tmp);
        s := s + tmp;
        s := s + ', y = ';
        Str(r.origin.y, tmp);
        s := s + tmp;
        s := s + ', width = ';
        Str(r.size.width, tmp);
        s := s + tmp;
        s := s + ', height = ';
        Str(r.size.height, tmp);
        s := s + tmp;
        s := s + ')';

        StringFromRect := s;

        { StringFromRect := 'Rect(x = ',r.origin.x, ', y = ', r.origin.y, +
        +', width = ', r.size.width, ', height = ', r.size.height, ')'; }
    end;

procedure DrawInRect(r :Rect);
    var
        x1, y1, x2, y2 : Integer;

    begin
        x1 := r.origin.x;
        y1 := r.origin.y;
        x2 := x1 + r.size.width;
        y2 := x2 + r.size.height;

        Window(x1, y1, x2, y2);
    end;

procedure WindowInRect(x, y, width, height : Integer);
    var
        r : Rect;

    begin
        r.origin.x    := x;
        r.origin.y    := y;
        r.size.width  := width;
        r.size.height := height;

        DrawInRect(r);
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
        counter, framerate : Integer;

    begin
        counter     := _ticker.timer.counter;
        framerate   := _ticker.timer.framerate;

		case _ticker.line.keyboardState of
			OSKeyboardTouchEnded: begin
    			inc(counter);
    			if counter >= MAX_COUNTER - framerate then begin
    				TICKER_DRAW;
    				counter := 0;
    			end;
			end;
		end;

        _ticker.timer.counter := counter;
    end;

{ 	////////////////////////////////////////////
	// pragma mark - Two streams //
}

function EMPTY: Boolean;
    begin
        EMPTY := _queue.counter >= _queue.time + _queue.excess;
    end;

function FEATURE(x: Integer): Boolean;
	begin
		FEATURE := sqrt(x) = round(sqrt(x));
	end;

function LVLBUF: Real;
    begin
        LVLBUF := _queue.iDx / BUFFER_SIZE;
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

        write('SERVER: ', _queue.itemIn:3, ' > ');
        textColor(serverArm);
        write(serverInf:7);
        writeln;

        write('CLIENT: ', _queue.itemOut:3, ' > ');
        textColor(clientArm);
        write(clientInf:7);
        writeln;
        writeln;

        for i := 1 to _queue.iDx do begin
            write(_queue.buffer[i], ' ');
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
		_queue.client.state     := OSPassive;

		_queue.item       := -1;
		_queue.itemIn     := 0;
		_queue.itemOut    := 0;
		_queue.iDx        := 0;

		_queue.time       := 0;
    end;

procedure CLIENT;
    begin
        _queue.counter := 0;
        while not EMPTY do begin
            if _queue.iDx > 0 then begin
                    _queue.client.state := OSActive;
                    _queue.itemOut := _queue.buffer[_queue.iDx];
                    Dec(_queue.iDx);
            end else begin
                    _queue.client.state := OSPassive;
                    _queue.excess := _queue.time + _queue.excess - _queue.counter;
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
    begin
        _queue.counter := 0;
        while not EMPTY do begin
            if _queue.iDx < BUFFER_SIZE then begin
                _queue.server.state := OSActive;

                repeat
                    inc(_queue.item);
                until FEATURE(_queue.item);

                _queue.itemIn := _queue.item;
                inc(_queue.iDx);
                _queue.buffer[_queue.iDx] := _queue.item;
            end	else begin
                _queue.server.state := OSPassive;
                _queue.excess := _queue.time + _queue.excess - _queue.counter;
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
            _queue.time := Random(MAX_TIME_SLICE) + 1;

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
	// pragma mark - INTERRUPT //
}

{ $F+ }
procedure TimeHandler; interrupt;
	begin
        TIME_TICKER_HANDLER;
        TIME_QUEUE_HANDLER;

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
                    DRAW_CONTROLL;
                end;
            end;

            13: begin
                framerate := _ticker.timer.framerate;
                if framerate < MAX_COUNTER then begin
                    Inc(framerate);
                    _ticker.timer.framerate := framerate;
                    DRAW_CONTROLL;
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
                DRAW_CONTROLL;
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
        ClrScr; { Clear all sumbols }

        DRAW_CONTROLL;
    end;

procedure INIT; { Setting the property }
    begin
        TICKER_INIT;

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

    QUEUE_INIT;

    ARGC;
    INIT;
    DRAW;

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

    SetIntVec($8, Addr(Systime));
    SetIntVec($9, Addr(Keyboard));

END.
