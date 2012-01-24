//
// Copyright (C) 2012 Intel Corporation
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//

#include <stdio.h>
#include <string.h>

#include "asim/syntax.h"
#include "asim/mesg.h"

#include "awb/provides/soft_services_deps.h"

//
// Global strings are a method of passing strings between hardware and software
// using a unique token instead of passing entire strings.
//

// Static objects
unordered_map <UINT32, string> GLOBAL_STRINGS::uidToString;
static GLOBAL_STRINGS instance;


//
// Look up a string in the table, given a UID.
//
const string*
GLOBAL_STRINGS::Lookup(UINT32 uid, bool abortIfUndef)
{
    unordered_map <UINT32, string>::iterator s = uidToString.find(uid);

    if (s != uidToString.end())
    {
        return &(s->second);
    }
    else
    {
        if (abortIfUndef)
        {
            ASIMERROR("Global string UID " << uid << " undefined!");
        }

        return NULL;
    }
}

//
// Add a string to the table.
//
void
GLOBAL_STRINGS::AddString(UINT32 uid, const string& str)
{
    unordered_map <UINT32, string>::iterator s = uidToString.find(uid);

    if (s != uidToString.end())
    {
        // UID already present!
        VERIFY(s->second.compare(str) == 0,
               "Strings \"" << s->second << "\" and \"" << str << "\" share UID " << uid);
        return;
    }

    uidToString[uid] = str;
}

//
// Read in a global string database built by the Bluespec compilation.
//
// The expected database is very simple.  No comments or whitespace.
// Each line is a of the form:
//   <uid>,<string>
//
void
GLOBAL_STRINGS::ProcessSwitchString(const char *db)
{
    FILE *f;

    f = fopen(db, "r");
    VERIFY(f != NULL, "Failed to open global string database " << db);

    int uid;
    while (fscanf(f, "%u,", &uid) == 1)
    {
        char buf[1024];
        if (fgets(buf, sizeof(buf), f) != NULL)
        {
            // Drop newline
            int end_idx = strlen(buf) - 1;
            if (end_idx >= 0 && buf[end_idx] == '\n') buf[end_idx] = 0;

            AddString(uid, buf);
        }
    }

    fclose(f);
}


GLOBAL_STRINGS::GLOBAL_STRINGS() : COMMAND_SWITCH_STRING_CLASS("global-strings")
{
}