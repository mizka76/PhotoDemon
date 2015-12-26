VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "pdListSupport"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon List Box support class
'Copyright 2015-2015 by Tanner Helland
'Created: 22/December/15
'Last updated: 22/December/15
'Last update: initial build
'
'PD makes use of a lot of custom-drawn list boxes.  To simplify these, I've tried to move a bunch of list-box-agnostic
' code elements into this class, elements that can then be reused by individual boxes.
'
'All source code in this file is licensed under a modified BSD license. This means you may use the code in your own
' projects IF you provide attribution. For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'This class can calculate list box element offsets using three different systems:
' - Fixed size (all list elements are the same height)
' - Separators (all list elements are the same height, but some have divider lines after them)
' - Custom size (the owner controls each element height independently)
'By default, fixed size is assumed.
Private m_SizeMode As PD_LISTBOX_HEIGHT

'If custom sizes are in use, PD needs to store each listbox item position independently, since we can't infer it.
' Note that this struct (and the corresponding position array) may or may not be in use - or certain parts of it
' may be in use, but not other - depending on the combination of parameters sent to us by the user.
Private Type PD_LISTITEM
    textEn As String
    textTranslated As String
    itemPosition As Long
    itemHeight As Long
    isSeparator As Boolean
End Type

Private m_Items() As PD_LISTITEM

'Current list item count.  May or may not correspond to the size of m_Items, FYI.
Private Const INITIAL_LIST_SIZE As Long = 16&
Private m_NumOfItems As Long

'Default height of a list box item.  This is controlled by the current font size, and automatically adjusted if/when the
' font size changes.
Private m_DefaultHeight As Long

'Total height of the entire list box, as it would appear without scrolling.  This is used to calculate scrollbar values.
Private m_TotalHeight As Long

'Divider height is calculated as a fraction of the default line height.  This makes things like DPI handling much simpler.
Private Const COMBO_BOX_DIVIDER_HEIGHT As Double = 0.75

'Font size is used to determine default line height.  You can ignore it if the box will be fully custom-drawn.
Private m_FontSize As Single

'This class will track .ListIndex for you.  It needs to know that value to auto-suggest things like scroll bar position
' after a keypress.
Private m_ListIndex As Long

Private Sub Class_Initialize()
    m_DefaultHeight = 0
    m_FontSize = 10
    m_SizeMode = PDLH_FIXED
    Me.Clear
End Sub

'Add an item to the list.  Note that all parameters are optional; if the owner is managing a list with custom data, for example,
' they do not need to pass strings to this function.  Similarly, things like separators and custom height can be happily
' ignored if those features are not required.
Public Sub AddItem(Optional ByVal srcItemText As String = vbNullString, Optional ByVal itemIndex As Long = -1, Optional ByVal hasTrailingSeparator As Boolean = False, Optional ByVal itemHeight As Long = -1)
    
    'Make sure there's room in the array for this item.
    If m_NumOfItems > UBound(m_Items) Then ReDim Preserve m_Items(0 To m_NumOfItems * 2 - 1) As PD_LISTITEM
    
    'Change the rendering mode, as necessary
    If CBool(itemHeight <> -1) And CBool(m_SizeMode <> PDLH_CUSTOM) Then
        m_SizeMode = PDLH_CUSTOM
    ElseIf hasTrailingSeparator And CBool(m_SizeMode <> PDLH_SEPARATORS) Then
        m_SizeMode = PDLH_SEPARATORS
    End If
    
    'If this item is being inserted anywhere but the end of the list, move other items around to make room.
    Dim i As Long
    If CBool(itemIndex <> -1) And CBool(itemIndex < m_NumOfItems) Then
        
        'Migrate all objects downward in the list.
        For i = m_NumOfItems To (itemIndex + 1) Step -1
            m_Items(i) = m_Items(i - 1)
        Next i
        
    'If no insert index has been specified, assume the insertion happens at the end of the list
    ElseIf CBool(itemIndex = -1) Then
        itemIndex = m_NumOfItems
    End If
    
    'Insert the given item
    With m_Items(itemIndex)
        .isSeparator = hasTrailingSeparator
        .textEn = srcItemText
        
        'Add a translated copy of the string as well; this will be the string actually rendered onto the screen.
        If Not (g_Language Is Nothing) Then
            If g_Language.translationActive Then
                .textTranslated = g_Language.TranslateMessage(srcItemText)
            Else
                .textTranslated = srcItemText
            End If
        Else
            .textTranslated = srcItemText
        End If
        
        'Calculating height is a bit more involved...
        If CBool(itemHeight = -1) Then
            
            If .isSeparator Then
                .itemHeight = m_DefaultHeight + (m_DefaultHeight * COMBO_BOX_DIVIDER_HEIGHT)
            Else
                .itemHeight = m_DefaultHeight
            End If
            
        'If the user specifies a height, assume it's correct.  Any positioning issues are theirs to deal with.
        Else
            .itemHeight = m_DefaultHeight
        End If
        
        'Increase the net height of the entire list
        m_TotalHeight = m_TotalHeight + m_DefaultHeight
        
        'Positioning values are really only used if separators are active, or if user-specified heights are involved,
        ' but right now we right those positions correctly for any insertion action.  (We can revisit in the future
        ' if performance becomes an issue.)
        If itemIndex < m_NumOfItems Then
            
            'Set the current item's position.
            If itemIndex = 0 Then
                .itemPosition = 0
            Else
                .itemPosition = m_Items(itemIndex - 1).itemPosition + m_Items(itemIndex - 1).itemHeight
            End If
            
            'Add this item's height to all subsequent positions.
            For i = itemIndex + 1 To m_NumOfItems
                m_Items(i).itemPosition = m_Items(i).itemPosition + .itemHeight
            Next i
        
        'If this item is being inserted at the end of the list, simply plug it into place.
        Else
            If itemIndex > 0 Then
                .itemPosition = m_Items(itemIndex - 1).itemPosition + m_Items(itemIndex - 1).itemHeight
            Else
                .itemPosition = 0
            End If
        End If
        
    End With
    
    'If this item is beneath the list index, bump up the list index by one
    If itemIndex < m_ListIndex Then m_ListIndex = m_ListIndex + 1
    
    'Increment the number of list entries
    m_NumOfItems = m_NumOfItems + 1
    
End Sub

'Reset the current list.  An optional starting list size can be passed; if it is not passed, it will default to INITIAL_LIST_SIZE.
Public Sub Clear(Optional ByVal newListSize As Long = INITIAL_LIST_SIZE)
    
    On Error GoTo FailsafeReset
    
    'Reset some obvious things (that don't require special handling)
    m_ListIndex = 0
    m_NumOfItems = 0
    m_TotalHeight = 0
    
    'Failsafe bounds check
    If newListSize <= 0 Then newListSize = INITIAL_LIST_SIZE
    
    'Reset the array (but only if necessary!)
    If m_NumOfItems = 0 Then
        ReDim m_Items(0 To newListSize - 1) As PD_LISTITEM
    Else
        If UBound(m_Items) = newListSize - 1 Then
            Dim i As Long
            For i = 0 To UBound(m_Items)
                With m_Items(i)
                    .isSeparator = False
                    .itemHeight = 0
                    .itemPosition = 0
                    .textEn = vbNullString
                    .textTranslated = vbNullString
                End With
            Next i
        Else
            ReDim m_Items(0 To newListSize - 1) As PD_LISTITEM
        End If
    End If
    
    m_NumOfItems = 0
    
    Exit Sub
    
FailsafeReset:
    If newListSize <= 0 Then newListSize = INITIAL_LIST_SIZE
    ReDim m_Items(0 To newListSize - 1) As PD_LISTITEM
    
End Sub

'Font size controls the default height of each list item.  When the font size changes, we need to recalculate a number of
' internal size metrics, so it's advisable to set this UP FRONT before doing anything else.
Public Property Get FontSize() As Single
    FontSize = m_FontSize
End Property

Public Property Let FontSize(ByVal newSize As Single)
    If m_FontSize <> newSize Then
        m_FontSize = newSize
        
        'Use that font size to calculate a default list item height
        m_DefaultHeight = Font_Management.GetDefaultStringHeight(m_FontSize)
        
        'If a non-standard size mode is in use, we would technically need to calculate new positioning metrics for
        ' all list items.  However, this isn't really feasible at present.  Instead, just don't change the damn font
        ' size after you've added custom-height items to the list box!
        
    End If
End Property

'Retrieve a specified list item
Public Function List(ByVal itemIndex As Long, Optional ByVal returnTranslatedText As Boolean = False) As String
    
    If (itemIndex >= 0) And (itemIndex < m_NumOfItems) Then
        If returnTranslatedText Then
            List = m_Items(itemIndex).textEn
        Else
            List = m_Items(itemIndex).textTranslated
        End If
    Else
        List = vbNullString
    End If
    
End Function

Public Function ListCount() As Long
    ListCount = m_NumOfItems
End Function

Public Property Get ListIndex() As Long
    ListIndex = m_ListIndex
End Property

Public Property Let ListIndex(ByVal newIndex As Long)
    If (newIndex >= 0) And (newIndex < m_NumOfItems) Then m_ListIndex = newIndex
End Property

'As a convenience, this class also lets the caller set a ListIndex by string.  (If a match cannot be found,
' the list index will not be changed.)
Public Sub ListIndexByString(ByRef srcString As String, Optional ByVal compareMode As VbCompareMethod = vbBinaryCompare)
    
    If m_NumOfItems > 0 Then
        
        Dim newIndex As Long
        newIndex = -1
        
        Dim i As Long
        For i = 0 To m_NumOfItems - 1
            If StrComp(srcString, m_Items(i).textEn, compareMode) = 0 Then
                newIndex = i
                Exit For
            End If
        Next i
        
        'If a match was found, change the list index now
        If (newIndex >= 0) And (newIndex <> m_ListIndex) Then m_ListIndex = newIndex
        
    End If
    
End Sub

'Remove an item from the combo box
Public Sub RemoveItem(ByVal itemIndex As Long)
    
    'First, make sure the requested index is valid
    If (itemIndex >= 0) And (itemIndex < m_NumOfItems) Then
        
        'Remove this item's size from the net height tracker
        Dim missingItemHeight As Long
        missingItemHeight = m_Items(itemIndex).itemHeight
        m_TotalHeight = m_TotalHeight - missingItemHeight
                
        'If this item is not being removed from the *end* of the list, shift everything past it downward.
        Dim i As Long
        If itemIndex < (m_NumOfItems - 1) Then
            For i = itemIndex To m_NumOfItems - 2
                m_Items(i) = m_Items(i + 1)
                m_Items(i).itemPosition = m_Items(i).itemPosition - missingItemHeight
            Next i
        End If
        
        'Reduce the total list size
        m_NumOfItems = m_NumOfItems - 1
        
        'If the removal affected the current ListIndex, update it to match
        If itemIndex <= m_ListIndex Then m_ListIndex = m_ListIndex - 1
        If m_ListIndex < 0 Then m_ListIndex = 0
        
    End If
    
End Sub
